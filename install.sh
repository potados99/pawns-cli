#!/usr/bin/env bash
# Install pawns-cli + systemd service on Linux (amd64/arm64).
#
# Usage:
#   wget -qO- https://raw.githubusercontent.com/potados99/pawns-cli/main/install.sh | bash

set -euo pipefail

REPO="potados99/pawns-cli"
BASE_URL="https://raw.githubusercontent.com/$REPO/main"
INSTALL_BIN="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
ENV_FILE="/etc/default/pawns-cli"

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
fetch "$TMP/pawns-cli" "$DIST_URL/pawns-cli"

echo "==> Downloading service files..."
fetch "$TMP/pawns-cli.service" "$SYSTEMD_URL/pawns-cli.service"
fetch "$TMP/pawns-watchdog.sh" "$SYSTEMD_URL/pawns-watchdog.sh"
fetch "$TMP/pawns-watchdog.service" "$SYSTEMD_URL/pawns-watchdog.service"
fetch "$TMP/pawns-watchdog.timer" "$SYSTEMD_URL/pawns-watchdog.timer"

echo "==> Installing (sudo required)..."
sudo install -m 755 "$TMP/pawns-cli" "$INSTALL_BIN/pawns-cli"

sudo install -m 644 "$TMP/pawns-cli.service" "$SYSTEMD_DIR/"
sudo install -m 644 "$TMP/pawns-watchdog.service" "$SYSTEMD_DIR/"
sudo install -m 644 "$TMP/pawns-watchdog.timer" "$SYSTEMD_DIR/"
sudo install -m 755 "$TMP/pawns-watchdog.sh" "$INSTALL_BIN/"

if [ ! -f "$ENV_FILE" ]; then
    sudo tee "$ENV_FILE" > /dev/null <<'ENVEOF'
EMAIL=you@example.com
PASSWORD=yourpassword
DEVICE_NAME=my-device
DEVICE_ID=my-device-id
ENVEOF
    echo "==> Created $ENV_FILE — edit it with your credentials"
else
    echo "==> $ENV_FILE already exists, skipping"
fi

sudo systemctl daemon-reload

echo ""
echo "==> Installed pawns-cli $VERSION"
echo ""
echo "Next steps:"
echo "  1. sudo vi $ENV_FILE              # set your email, password, device name/id"
echo "  2. sudo systemctl enable --now pawns-cli pawns-watchdog.timer"
echo "  3. journalctl -u pawns-cli -f      # watch logs"
