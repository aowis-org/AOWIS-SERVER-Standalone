#!/usr/bin/env bash

#git submodule update --recursive --remote

set -euo pipefail

git submodule sync --recursive
git submodule update --init --recursive --remote --jobs 8
git submodule status --recursive

#git -C AOWIS-SERVER-GUI/external/AOWIS-SERVER-EPANET fetch origin main && \
#git -C AOWIS-SERVER-GUI/external/AOWIS-SERVER-EPANET switch -C main origin/main

