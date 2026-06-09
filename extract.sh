#!/usr/bin/env bash
# Extract pawns-cli binary from the official Docker image.
# Supports both amd64 and arm64.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="iproyal/pawns-cli"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  PLATFORM="linux/amd64" ;;
    aarch64) PLATFORM="linux/arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

echo "==> Pulling $IMAGE:latest ($PLATFORM)"
docker pull --platform "$PLATFORM" "$IMAGE:latest"

echo "==> Fetching version from Docker Hub..."
VERSION=$(curl -s "https://hub.docker.com/v2/repositories/iproyal/pawns-cli/tags/?page_size=5&ordering=-last_updated" \
    | python3 -c "
import sys, json
tags = json.load(sys.stdin)['results']
versions = [t['name'] for t in tags if t['name'] != 'latest' and t['name'][0].isdigit()]
print(versions[0] if versions else '')
")

if [ -z "$VERSION" ]; then
    echo "Failed to get version." >&2
    exit 1
fi
echo "==> Version: $VERSION"

DIST_DIR="$SCRIPT_DIR/dist/$VERSION"

if [ -d "$DIST_DIR" ]; then
    echo "==> Already extracted: $DIST_DIR"
    echo "    Remove the directory and re-run to overwrite."
    exit 0
fi

mkdir -p "$DIST_DIR"

CONTAINER=$(docker create --platform "$PLATFORM" "$IMAGE:latest")
trap "docker rm $CONTAINER > /dev/null 2>&1" EXIT

echo "==> Extracting binary..."
docker cp "$CONTAINER:/pawns-cli" "$DIST_DIR/pawns-cli"

echo "$VERSION" > "$SCRIPT_DIR/latest"

echo ""
echo "==> Done:"
ls -lh "$DIST_DIR"
echo ""
echo "latest -> $VERSION"
