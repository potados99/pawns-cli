#!/usr/bin/env bash
# Watchdog for pawns-cli: detects a hung process and restarts the service.

set -euo pipefail

SERVICE="pawns-cli.service"
TIMEOUT=600  # 10 minutes with no log output → consider hung

if ! systemctl is-active --quiet "$SERVICE"; then
    if systemctl is-failed --quiet "$SERVICE"; then
        echo "pawns-cli is in failed state (start limit hit?). Resetting and restarting."
        systemctl reset-failed "$SERVICE"
        systemctl start "$SERVICE"
    fi
    exit 0
fi

PID=$(systemctl show "$SERVICE" --property=MainPID --value)
if [ "$PID" = "0" ] || [ -z "$PID" ]; then
    exit 0
fi

LAST_LOG_EPOCH=$(journalctl -u "$SERVICE" -n 1 --output=short-unix --no-pager 2>/dev/null \
    | tail -1 | awk '{print int($1)}')
NOW_EPOCH=$(date +%s)

if [ -z "$LAST_LOG_EPOCH" ] || [ "$LAST_LOG_EPOCH" = "0" ]; then
    exit 0
fi

SILENT_FOR=$((NOW_EPOCH - LAST_LOG_EPOCH))

if [ "$SILENT_FOR" -gt "$TIMEOUT" ]; then
    echo "pawns-cli has been silent for ${SILENT_FOR}s (threshold: ${TIMEOUT}s). Restarting."
    systemctl restart "$SERVICE"
fi
