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
  GOJO_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || \
    cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32 | \
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

  sed -i "s|GOJO_IP_PLACEHOLDER|${GOJO_IP}|g" "$CONFIG"
  sed -i "s|GOJO_PORT_PLACEHOLDER|${GOJO_PORT}|g" "$CONFIG"
  sed -i "s|GOJO_PASSWORD_PLACEHOLDER|${GOJO_PASSWORD}|g" "$CONFIG"
  sed -i "s|GOJO_PROTO_PATH_PLACEHOLDER|${GOJO_PROTO_PATH}|g" "$CONFIG"

  # Set routing to use chain-out
  sed -i 's|"outboundTag": "direct"|"outboundTag": "chain-out"|g' "$CONFIG"

else
  # Remove chain-out outbound block — direct mode
  # Keep only direct + block outbounds via python inline
  python3 -c "
import json, sys
with open('${CONFIG}') as f:
  c = json.load(f)
c['outbounds'] = [o for o in c['outbounds'] if o['tag'] != 'chain-out']
with open('${CONFIG}', 'w') as f:
  json.dump(c, f, indent=2)
"
fi

# =========================
# EXPORT FOR LANDING PAGE
# =========================

export GOJO_UUID
export GOJO_FULL_PATH
export GOJO_IP

# Save to file para mabasa ng nginx/index.html
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
