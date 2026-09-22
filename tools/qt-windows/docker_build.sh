#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker build \
  --network=host \
  -f "$SCRIPT_DIR/Dockerfile.qt-windows" \
  -t aowis-qt-windows:6.7 \
  "$SCRIPT_DIR"
