#!/bin/sh
set -e

# =========================
# GOJO-RELAY ENTRYPOINT
# =========================

CONFIG="/etc/xray/config.json"

# =========================
# GENERATE UUID IF EMPTY
# =========================

if [ -z "$GOJO_UUID" ]; then
  GOJO_UUID=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32 | \
    sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
fi

# =========================
# GENERATE SUFFIX IF EMPTY
# =========================

if [ -z "$GOJO_SUFFIX" ]; then
  GOJO_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
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

  # Inject common placeholders
  sed -i "s|GOJO_IP_PLACEHOLDER|${GOJO_IP}|g" "$CONFIG"
  sed -i "s|\"GOJO_PORT_PLACEHOLDER\"|${GOJO_PORT}|g" "$CONFIG"
  sed -i "s|GOJO_PASSWORD_PLACEHOLDER|${GOJO_PASSWORD}|g" "$CONFIG"
  sed -i "s|GOJO_PROTO_PATH_PLACEHOLDER|${GOJO_PROTO_PATH}|g" "$CONFIG"
  sed -i "s|GOJO_SS_METHOD_PLACEHOLDER|${GOJO_SS_METHOD}|g" "$CONFIG"

  # Determine which chain tag to use
  case "$GOJO_PROTO" in
    vmess)  CHAIN_TAG="chain-vmess" ;;
    vless)  CHAIN_TAG="chain-vless" ;;
    ss)     CHAIN_TAG="chain-ss" ;;
    *)      CHAIN_TAG="chain-trojan" ;;
  esac

  # Remove unused chain outbounds — keep only selected
  python3 -c "
import json
with open('${CONFIG}') as f:
  c = json.load(f)
keep = ['direct', 'block', '${CHAIN_TAG}']
c['outbounds'] = [o for o in c['outbounds'] if o['tag'] in keep]
# Set routing to use selected chain
for rule in c.get('routing', {}).get('rules', []):
  if rule.get('outboundTag') == 'direct':
    rule['outboundTag'] = '${CHAIN_TAG}'
# Set default outbound to chain
c['outbounds'] = sorted(c['outbounds'], key=lambda x: 0 if x['tag'] == '${CHAIN_TAG}' else 1)
with open('${CONFIG}', 'w') as f:
  json.dump(c, f, indent=2)
"

else
  # Direct mode — tanggalin lahat ng chain outbounds
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
  "pointed": $([ -n "$GOJO_IP" ] && echo "true" || echo "false")
}
EOF

# =========================
# START SUPERVISORD
# =========================

exec supervisord -c /etc/supervisord.conf
