#!/bin/sh
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if nc -z 127.0.0.1 10001 2>/dev/null; then
    exec nginx -g "daemon off;"
  fi
  sleep 1
  RETRY_COUNT=$((RETRY_COUNT + 1))
done
echo "ERROR: Xray did not become ready in time" >&2
exit 1
