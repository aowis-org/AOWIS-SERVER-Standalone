#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
docker build --network=host --pull \
    -f Dockerfile.qt-windows \
    -t aowis-qt-windows:6.12.0-mingw15 .
