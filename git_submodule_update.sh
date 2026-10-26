#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# If this was installed from a ZIP patch, register DVMDB's gitlink first.
if [[ "$(git ls-files --stage -- AOWIS-SERVER-DVMDB)" != '160000 '* ]]; then
    ./git_submodule_init.sh
fi

git submodule sync -- AOWIS-SERVER-GUI AOWIS-SERVER-MAP AOWIS-SERVER-DVMDB
# Advance just the Standalone top-level submodules, not DVMDB's nested Model.
git submodule update --init --remote --jobs 8 -- \
    AOWIS-SERVER-GUI AOWIS-SERVER-MAP AOWIS-SERVER-DVMDB

(
    cd AOWIS-SERVER-GUI
    ./git_submodule_init.sh
)

git submodule status
printf '\nReview and commit updated Standalone gitlinks, then configure/build.\n'
printf 'DVMDB reuses GUI\047s pinned Model; the codec check will reject incompatible revisions.\n'
