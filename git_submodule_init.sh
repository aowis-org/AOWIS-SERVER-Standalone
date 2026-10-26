#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

dvmdb_path='AOWIS-SERVER-DVMDB'
dvmdb_url='https://github.com/aowis-org/AOWIS-SERVER-DVMDB.git'

# A ZIP patch can add .gitmodules but cannot register a submodule gitlink
# (index mode 160000). Bootstrap it in the actual Git checkout on first use.
if [[ "$(git ls-files --stage -- "$dvmdb_path")" != '160000 '* ]]; then
    if [[ -e "$dvmdb_path" && -n "$(ls -A -- "$dvmdb_path")" ]]; then
        printf 'Cannot register %s: its path is occupied by non-submodule files.\n' "$dvmdb_path" >&2
        exit 1
    fi
    printf 'Registering %s as a Git submodule...\n' "$dvmdb_path"
    git submodule add -- "$dvmdb_url" "$dvmdb_path"
    printf '\nIMPORTANT: Commit the new DVMDB gitlink in Standalone:\n'
    printf '  git add .gitmodules %s\n' "$dvmdb_path"
    printf '  git commit -m "Add DVMDB submodule"\n\n'
fi

git submodule sync -- AOWIS-SERVER-GUI AOWIS-SERVER-MAP "$dvmdb_path"
# NOT --recursive: DVMDB's nested Model is intentionally unused.
git submodule update --init --jobs 8 -- AOWIS-SERVER-GUI AOWIS-SERVER-MAP "$dvmdb_path"

# GUI is the only owner of the Model checkout. Its script also initializes
# its pinned EPANET, GeographicLib and bgfx dependencies.
(
    cd AOWIS-SERVER-GUI
    ./git_submodule_init.sh
)

git submodule status
