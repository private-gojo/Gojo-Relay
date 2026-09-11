#!/bin/sh

# =========================
# GOJO-RELAY ENTRYPOINT
# =========================

CONFIG="/etc/xray/config.json"

# =========================
# STRIP JSONC COMMENTS (xray runtime doesn't accept them)
# =========================
python3 -c "
import re
with open('$CONFIG') as f:
    s = f.read()
s = re.sub(r'(\"(?:\\\\.|[^\"\\\\])*\")|//.*?$|/\*.*?\*/', lambda m: m.group(1) if m.group(1) else '', s, flags=re.MULTILINE|re.DOTALL)
with open('$CONFIG', 'w') as f:
    f.write(s)
"

# =========================
# GET CLOUD RUN IP FIRST (via metadata + fallback)
# =========================

set +e
SERVER_IP=$(curl -s --max-time 3 -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null)

if [ -z "$SERVER_IP" ]; then
  SERVER_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ipify.org || echo "")
fi
set -e

# =========================
# GENERATE UUID IF EMPTY
# =========================

if [ -z "$GOJO_UUID" ]; then
  if [ -f /proc/sys/kernel/random/uuid ]; then
    GOJO_UUID=$(cat /proc/sys/kernel/random/uuid)
  else
    GOJO_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")
  fi
fi

# =========================
# GENERATE SUFFIX IF EMPTY
# =========================

if [ -z "$GOJO_SUFFIX" ]; then
  set +e
  GOJO_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
  set -e
fi

# =========================
# BUILD PATH
# =========================

GOJO_FULL_PATH="/gojo/infinity-limitless/${GOJO_SUFFIX}?ed=2560"

# =========================
# INJECT UUID + PATH
# =========================

sed -i "s|GOJO_UUID_PLACEHOLDER|${GOJO_UUID}|g" "$CONFIG"
sed -i "s|GOJO_PATH_PLACEHOLDER|${GOJO_FULL_PATH}|g" "$CONFIG"

# =========================
# CHAIN OUTBOUND (OPTIONAL)
# Points relay to an external exit node (trojan/vmess/vless/ss)
# instead of direct connection, if GOJO_IP is set
# =========================

if [ -n "$GOJO_IP" ]; then

  GOJO_PORT=${GOJO_PORT:-443}
  GOJO_PASS=${GOJO_PASS:-""}
  GOJO_PROTO=${GOJO_PROTO:-"trojan"}
  GOJO_XPATH=${GOJO_XPATH:-"/"}
  GOJO_SS=${GOJO_SS:-"chacha20-ietf-poly1305"}
  GOJO_SEC=${GOJO_SEC:-"tls"}
  GOJO_AID=${GOJO_AID:-0}

  sed -i "s|GOJO_IP_PLACEHOLDER|${GOJO_IP}|g" "$CONFIG"
  sed -i "s|\"GOJO_PORT_PLACEHOLDER\"|${GOJO_PORT}|g" "$CONFIG"
  sed -i "s|GOJO_PASS_PLACEHOLDER|${GOJO_PASS}|g" "$CONFIG"
  sed -i "s|GOJO_XPATH_PLACEHOLDER|${GOJO_XPATH}|g" "$CONFIG"
  sed -i "s|GOJO_SS_PLACEHOLDER|${GOJO_SS}|g" "$CONFIG"
  sed -i "s|GOJO_SEC_PLACEHOLDER|${GOJO_SEC}|g" "$CONFIG"
  sed -i "s|\"GOJO_AID_PLACEHOLDER\"|${GOJO_AID}|g" "$CONFIG"

  # Keep only the selected protocol's outbound + direct/block
  case "$GOJO_PROTO" in
    vmess)  CHAIN_TAG="chain-vmess" ;;
    trojan) CHAIN_TAG="chain-trojan" ;;
    ss)     CHAIN_TAG="chain-ss" ;;
    *)      CHAIN_TAG="chain-vless" ;;
  esac

  python3 -c "
import json
with open('${CONFIG}') as f:
  c = json.load(f)
keep = ['direct', 'block', '${CHAIN_TAG}']
c['outbounds'] = [o for o in c['outbounds'] if o['tag'] in keep]
c['outbounds'] = sorted(c['outbounds'], key=lambda x: 0 if x['tag'] == '${CHAIN_TAG}' else 1)
c['routing']['rules'].append({'type': 'field', 'network': 'tcp,udp', 'outboundTag': '${CHAIN_TAG}'})
with open('${CONFIG}', 'w') as f:
  json.dump(c, f, indent=2)
"

else
  # No chain outbound - keep only direct/block, relay connects straight out
  python3 -c "
import json
with open('${CONFIG}') as f:
  c = json.load(f)
c['outbounds'] = [o for o in c['outbounds'] if o['tag'] in ['direct', 'block']]
with open('${CONFIG}', 'w') as f:
  json.dump(c, f, indent=2)
"
fi

# =========================
# RUNTIME JSON
# Written for nginx (/runtime.json endpoint) and sub_server.py to read
# =========================

cat > /etc/xray/runtime.json <<EOF
{
  "uuid": "${GOJO_UUID}",
  "path": "${GOJO_FULL_PATH}",
  "pointed": $([ -n "$GOJO_IP" ] && echo "true" || echo "false"),
  "server_ip": "${SERVER_IP}"
}
EOF

# =========================
# START SUPERVISORD
# Hands off to supervisord, which launches nginx (via wait-for-xray.sh),
# xray, and sub_server
# =========================

exec supervisord -c /etc/supervisord.conf
