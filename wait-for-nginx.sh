#!/bin/sh

# =========================
# WAIT-FOR-NGINX
# Purpose: Prevents anti_ddos.py from starting before Nginx is ready
# on port 8082 (same startup race condition class as wait-for-xray.sh,
# now one layer up since anti_ddos.py sits in front of Nginx)
# =========================

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if nc -z 127.0.0.1 8082 2>/dev/null; then
    exec python3 /anti_ddos.py
  fi
  sleep 1
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

echo "ERROR: Nginx did not become ready in time" >&2
exit 1
