#!/usr/bin/env bash
# Install pawns-cli + systemd service on Linux (amd64/arm64).
#
# Usage:
#   wget -qO- https://raw.githubusercontent.com/potados99/pawns-cli/main/install.sh | bash -s -- \
#     --email you@example.com --password yourpass --device-name my-device --device-id my-id
#
# Re-running updates the binary and service files.
# Credentials are only written if --email/--password are provided or no env file exists.

set -euo pipefail

REPO="potados99/pawns-cli"
BASE_URL="https://raw.githubusercontent.com/$REPO/main"
INSTALL_BIN="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
ENV_FILE="/etc/default/pawns-cli"

# --- Parse arguments ---
ARG_EMAIL=""
ARG_PASSWORD=""
ARG_DEVICE=""
ARG_DEVICE_ID=""
ARG_HEARTBEAT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --email)         ARG_EMAIL="$2"; shift 2 ;;
        --password)      ARG_PASSWORD="$2"; shift 2 ;;
        --device-name)   ARG_DEVICE="$2"; shift 2 ;;
        --device-id)     ARG_DEVICE_ID="$2"; shift 2 ;;
        --heartbeat-url) ARG_HEARTBEAT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- HTTP fetcher ---
if command -v curl &>/dev/null; then
    fetch() { curl -fsSL -o "$1" "$2"; }
    fetch_stdout() { curl -fsSL "$1"; }
elif command -v wget &>/dev/null; then
    fetch() { wget -qO "$1" "$2"; }
    fetch_stdout() { wget -qO- "$1"; }
else
    echo "curl or wget is required." >&2
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|aarch64) ;;
    *)
        echo "Unsupported architecture: $ARCH (only x86_64 and aarch64)" >&2
        exit 1
        ;;
esac

echo "==> Fetching latest version..."
VERSION=$(fetch_stdout "$BASE_URL/latest")
if [ -z "$VERSION" ]; then
    echo "Failed to get version info." >&2
    exit 1
fi
echo "    Version: $VERSION"

DIST_URL="$BASE_URL/dist/$VERSION"
SYSTEMD_URL="$BASE_URL/systemd"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "==> Downloading binary..."
case "$ARCH" in
    x86_64)  BINARY_NAME="pawns-cli" ;;
    aarch64) BINARY_NAME="pawns-cli-arm64" ;;
esac
fetch "$TMP/pawns-cli" "$DIST_URL/$BINARY_NAME"

echo "==> Downloading service files..."
fetch "$TMP/pawns-cli.service" "$SYSTEMD_URL/pawns-cli.service"
fetch "$TMP/pawns-watchdog.sh" "$SYSTEMD_URL/pawns-watchdog.sh"
fetch "$TMP/pawns-watchdog.service" "$SYSTEMD_URL/pawns-watchdog.service"
fetch "$TMP/pawns-watchdog.timer" "$SYSTEMD_URL/pawns-watchdog.timer"

echo "==> Installing..."
sudo install -m 755 "$TMP/pawns-cli" "$INSTALL_BIN/pawns-cli"

sudo install -m 644 "$TMP/pawns-cli.service" "$SYSTEMD_DIR/"
sudo install -m 644 "$TMP/pawns-watchdog.service" "$SYSTEMD_DIR/"
sudo install -m 644 "$TMP/pawns-watchdog.timer" "$SYSTEMD_DIR/"
sudo install -m 755 "$TMP/pawns-watchdog.sh" "$INSTALL_BIN/"

# --- Credentials ---
if [ -n "$ARG_EMAIL" ] || [ ! -f "$ENV_FILE" ]; then
    sudo tee "$ENV_FILE" > /dev/null <<ENVEOF
EMAIL=${ARG_EMAIL:-you@example.com}
PASSWORD=${ARG_PASSWORD:-yourpassword}
DEVICE_NAME=${ARG_DEVICE:-my-device}
DEVICE_ID=${ARG_DEVICE_ID:-my-device-id}
HEARTBEAT_URL=${ARG_HEARTBEAT:-}
ENVEOF
    sudo chmod 600 "$ENV_FILE"
    if [ -z "$ARG_EMAIL" ]; then
        echo "==> Created $ENV_FILE with placeholders — edit it with your credentials"
    else
        echo "==> Wrote credentials to $ENV_FILE"
    fi
else
    echo "==> $ENV_FILE already exists, keeping current credentials"
fi

sudo systemctl daemon-reload

# --- Start or restart service ---
if systemctl is-active --quiet pawns-cli; then
    echo "==> Restarting pawns-cli service..."
    sudo systemctl restart pawns-cli
elif [ -n "$ARG_EMAIL" ]; then
    echo "==> Starting pawns-cli service..."
    sudo systemctl enable --now pawns-cli pawns-watchdog.timer
else
    echo ""
    echo "Next steps:"
    echo "  1. sudo vi $ENV_FILE"
    echo "  2. sudo systemctl enable --now pawns-cli pawns-watchdog.timer"
fi

echo ""
echo "==> Done (pawns-cli $VERSION)"
