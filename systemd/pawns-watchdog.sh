#!/usr/bin/env bash
# Watchdog for pawns-cli: health check + heartbeat to Uptime Kuma.

set -euo pipefail

SERVICE="pawns-cli.service"
ENV_FILE="/etc/default/pawns-cli"
NOT_RUNNING_GRACE=300   # seconds to let a dropped tunnel self-recover before restarting

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

# Service not running (crashed/failed)
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

PID=$(systemctl show "$SERVICE" --property=MainPID --value)
if [ "$PID" = "0" ] || [ -z "$PID" ]; then
    exit 0
fi

# Health: pawns must reach AND stay in the "running" state (reverse-proxy tunnel up) to earn.
# Two stuck modes leave the process "active" (so systemd never acts):
#   (a) never reached "running" since start  (tunnel dial hung, e.g. after a host reboot)
#   (b) reached "running" then dropped to "not_running" and never recovered (tunnel died,
#       e.g. websocket close / could_not_mark_peer_alive) — observed stuck for hours.
# Decide from the MOST RECENT lifecycle event since the service started. A pawns whose latest
# event is "running" is healthy even when silent, so this never false-restarts a working node.
ENTER=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value "$SERVICE")" +%s 2>/dev/null || echo 0)
NOW=$(date +%s)
UP=$(( ENTER > 0 ? NOW - ENTER : 0 ))
LAST_EVT=$(journalctl -u "$SERVICE" --since "@$ENTER" --no-pager -o cat 2>/dev/null \
    | grep -oE '"name":"(running|not_running)"' | tail -1 || true)

if [ "$LAST_EVT" = '"name":"not_running"' ]; then
    # tunnel currently down; give it a grace window to self-recover, else restart
    NR_TS=$(journalctl -u "$SERVICE" --since "@$ENTER" --no-pager -o short-unix 2>/dev/null \
        | grep not_running | tail -1 | awk '{print int($1)}')
    DOWN_FOR=$(( NR_TS > 0 ? NOW - NR_TS : 0 ))
    if [ "$DOWN_FOR" -gt "$NOT_RUNNING_GRACE" ]; then
        echo "pawns-cli stuck in not_running for ${DOWN_FOR}s — restarting."
        heartbeat "down" "${LABEL}:+not_running+${DOWN_FOR}s,+restarting"
        systemctl restart "$SERVICE"
    else
        heartbeat "down" "${LABEL}:+not_running+(grace)"
    fi
    exit 0
fi

if [ -z "$LAST_EVT" ] && [ "$UP" -gt 180 ]; then
    # active but never reached running/not_running — stalled before opening the tunnel
    echo "pawns-cli active ${UP}s but never reached running — restarting."
    heartbeat "down" "${LABEL}:+stalled+no+running,+restarting"
    systemctl restart "$SERVICE"
    exit 0
fi

# Latest event is "running" (or just started, <180s, no events yet) → healthy
heartbeat "up" "${LABEL}:+ok"
