#!/usr/bin/env bash
# Watchdog for pawns-cli: health check + heartbeat to Uptime Kuma.

set -euo pipefail

SERVICE="pawns-cli.service"
ENV_FILE="/etc/default/pawns-cli"

# Load env for HEARTBEAT_URL and DEVICE_NAME
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
fi

heartbeat() {
    local status="$1" msg="$2"
    if [ -n "${HEARTBEAT_URL:-}" ]; then
        wget -qO /dev/null --timeout=10 "${HEARTBEAT_URL}?status=${status}&msg=${msg}" 2>/dev/null || true
    fi
}

LABEL="${DEVICE_NAME:-unknown}"

# Service not running
if ! systemctl is-active --quiet "$SERVICE"; then
    if systemctl is-failed --quiet "$SERVICE"; then
        systemctl reset-failed "$SERVICE"
        systemctl start "$SERVICE"
        heartbeat "down" "${LABEL}:+restarted+from+failed"
    else
        heartbeat "down" "${LABEL}:+service+not+running"
    fi
    exit 0
fi

# Process alive → up
heartbeat "up" "${LABEL}:+ok"
