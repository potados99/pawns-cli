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

# Stall detection. pawns must reach the "running" state (reverse-proxy tunnel established)
# to actually earn. After a host reboot the tunnel dial can hang, leaving the process alive
# but stuck before "running" — silent, so a plain silence check would miss it. We instead
# check: if active for >3 min but "running" never appeared since the last start, it's stalled.
# A pawns that DID reach "running" is healthy even when quiet, so this never false-restarts.
ENTER=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value "$SERVICE")" +%s 2>/dev/null || echo 0)
NOW=$(date +%s)
if [ "$ENTER" != "0" ] && [ $((NOW - ENTER)) -gt 180 ]; then
    RAN=$(journalctl -u "$SERVICE" --since "@$ENTER" --no-pager -o cat 2>/dev/null | grep -c '"running"' || true)
    if [ "$RAN" -eq 0 ]; then
        echo "pawns-cli active $((NOW - ENTER))s but never reached 'running' — stalled. restarting."
        heartbeat "down" "${LABEL}:+stalled+no+running,+restarting"
        systemctl restart "$SERVICE"
        exit 0
    fi
fi

# Process alive and earning → up
heartbeat "up" "${LABEL}:+ok"
