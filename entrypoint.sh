#!/bin/sh

# =========================
# GOJO-RELAY ENTRYPOINT
# =========================

CONFIG="/etc/xray/config.json"

# =========================
# GET CLOUD RUN IP FIRST (before Xray/chain)
# =========================

set +e
SERVER_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ipify.org || echo "")
set -e

# =========================
# GENERATE UUID IF EMPTY
# Fix: SIGPIPE issue sa Alpine — gamitin /proc o python3
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
# Fix: set +e para hindi mag-exit sa SIGPIPE
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
# =========================

if [ -n "$GOJO_IP" ]; then

  GOJO_PORT=${GOJO_PORT:-443}
  GOJO_PASSWORD=${GOJO_PASSWORD:-""}
  GOJO_PROTO=${GOJO_PROTO:-"trojan"}
  GOJO_PROTO_PATH=${GOJO_PROTO_PATH:-"/"}
  GOJO_SS_METHOD=${GOJO_SS_METHOD:-"chacha20-ietf-poly1305"}

  sed -i "s|GOJO_IP_PLACEHOLDER|${GOJO_IP}|g" "$CONFIG"
  sed -i "s|\"GOJO_PORT_PLACEHOLDER\"|${GOJO_PORT}|g" "$CONFIG"
  sed -i "s|GOJO_PASSWORD_PLACEHOLDER|${GOJO_PASSWORD}|g" "$CONFIG"
  sed -i "s|GOJO_PROTO_PATH_PLACEHOLDER|${GOJO_PROTO_PATH}|g" "$CONFIG"
  sed -i "s|GOJO_SS_METHOD_PLACEHOLDER|${GOJO_SS_METHOD}|g" "$CONFIG"

  case "$GOJO_PROTO" in
    vmess)  CHAIN_TAG="chain-vmess" ;;
    vless)  CHAIN_TAG="chain-vless" ;;
    ss)     CHAIN_TAG="chain-ss" ;;
    *)      CHAIN_TAG="chain-trojan" ;;
  esac

  python3 -c "
import json
with open('${CONFIG}') as f:
  c = json.load(f)
keep = ['direct', 'block', '${CHAIN_TAG}']
c['outbounds'] = [o for o in c['outbounds'] if o['tag'] in keep]
c['outbounds'] = sorted(c['outbounds'], key=lambda x: 0 if x['tag'] == '${CHAIN_TAG}' else 1)
c['routing']['rules'] = [{'type': 'field', 'network': 'tcp,udp', 'outboundTag': '${CHAIN_TAG}'}]
with open('${CONFIG}', 'w') as f:
  json.dump(c, f, indent=2)
"

else
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
# RUNTIME JSON PARA SA LANDING PAGE
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
# =========================

exec supervisord -c /etc/supervisord.conf
