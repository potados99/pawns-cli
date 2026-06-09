#!/usr/bin/env bash
# Watchdog for pawns-cli: health check + heartbeat to Uptime Kuma.

set -euo pipefail

SERVICE="pawns-cli.service"
ENV_FILE="/etc/default/pawns-cli"
SILENT_TIMEOUT=600

# Load env for HEARTBEAT_URL and DEVICE_NAME
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
fi

heartbeat() {
    local status="$1" msg="$2"
    if [ -n "${HEARTBEAT_URL:-}" ]; then
        curl -fsS -m 10 "${HEARTBEAT_URL}?status=${status}&msg=${msg}" >/dev/null 2>&1 || true
    fi
}

LABEL="${DEVICE_NAME:-unknown}"

# Service not running
if ! systemctl is-active --quiet "$SERVICE"; then
    if systemctl is-failed --quiet "$SERVICE"; then
        echo "pawns-cli is in failed state (start limit hit?). Resetting and restarting."
        systemctl reset-failed "$SERVICE"
        systemctl start "$SERVICE"
        heartbeat "up" "${LABEL}:+recovered+from+failed+state"
    else
        heartbeat "down" "${LABEL}:+service+not+running"
    fi
    exit 0
fi

PID=$(systemctl show "$SERVICE" --property=MainPID --value)
if [ "$PID" = "0" ] || [ -z "$PID" ]; then
    exit 0
fi

# Check: silent hang
LAST_LOG_EPOCH=$(journalctl -u "$SERVICE" -n 1 --output=short-unix --no-pager 2>/dev/null \
    | tail -1 | awk '{print int($1)}')
NOW_EPOCH=$(date +%s)

if [ -n "$LAST_LOG_EPOCH" ] && [ "$LAST_LOG_EPOCH" != "0" ]; then
    SILENT_FOR=$((NOW_EPOCH - LAST_LOG_EPOCH))
    if [ "$SILENT_FOR" -gt "$SILENT_TIMEOUT" ]; then
        echo "pawns-cli silent for ${SILENT_FOR}s. Restarting."
        heartbeat "down" "${LABEL}:+silent+for+${SILENT_FOR}s,+restarting"
        systemctl restart "$SERVICE"
        exit 0
    fi
fi

# All good
heartbeat "up" "${LABEL}:+ok"
