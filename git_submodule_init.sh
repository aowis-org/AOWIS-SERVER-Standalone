#!/usr/bin/env bash

set -euo pipefail

git submodule sync
git submodule update --init --jobs 8 AOWIS-SERVER-GUI AOWIS-SERVER-MAP

(
    cd AOWIS-SERVER-GUI
    ./git_submodule_init.sh
)

git submodule status
