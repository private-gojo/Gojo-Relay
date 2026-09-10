#!/bin/sh

# =========================
# WAIT-FOR-XRAY
# Purpose: Prevents nginx from starting before Xray is ready
# on port 10001 (fixes startup race condition / 502 errors)
# =========================

MAX_RETRIES=30
RETRY_COUNT=0

# =========================
# POLL LOOP - Check if Xray's port is open
# =========================
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if nc -z 127.0.0.1 10001 2>/dev/null; then
    # =========================
    # XRAY READY - Launch nginx
    # =========================
    exec nginx -g "daemon off;"
  fi
  sleep 1
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

# =========================
# TIMEOUT - Xray never became ready
# =========================
echo "ERROR: Xray did not become ready in time" >&2
exit 1
