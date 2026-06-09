#!/usr/bin/env bash
# Install pawns-cli on Linux systems (amd64/arm64).
#
# Usage:
#   wget -qO- https://raw.githubusercontent.com/potados99/pawns-cli/main/install.sh | bash

set -euo pipefail

REPO="potados99/pawns-cli"
BASE_URL="https://raw.githubusercontent.com/$REPO/main"
INSTALL_BIN="/usr/local/bin"

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

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "==> Downloading pawns-cli..."
fetch "$TMP/pawns-cli" "$DIST_URL/pawns-cli"

echo "==> Installing (sudo required)..."
sudo install -m 755 "$TMP/pawns-cli" "$INSTALL_BIN/pawns-cli"

echo ""
echo "==> Installed pawns-cli $VERSION"
echo ""
echo "Usage:"
echo "  pawns-cli -email you@example.com -password yourpass -device-name my-device -device-id my-id -accept-tos"
