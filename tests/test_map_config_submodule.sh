#!/usr/bin/env bash
set -euo pipefail

# Offline integration test: verifies pinned MAP->CONFIG checkout, repeated
# initialization, and fail-closed behavior when MAP has only .gitmodules.
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
export GIT_ALLOW_PROTOCOL=file
export GIT_AUTHOR_NAME='AOWIS Test'
export GIT_AUTHOR_EMAIL='test@example.invalid'
export GIT_COMMITTER_NAME='AOWIS Test'
export GIT_COMMITTER_EMAIL='test@example.invalid'

make_repository() {
    git init -q -b main "$1"
}
commit_all() {
    git -C "$1" add -A
    git -C "$1" commit -qm "$2"
}

config_src="$temporary/config-source"
map_src="$temporary/map-source"
standalone_src="$temporary/standalone-source"
checkout="$temporary/checkout"

make_repository "$config_src"
printf 'cmake_minimum_required(VERSION 3.21)\n' > "$config_src/CMakeLists.txt"
commit_all "$config_src" 'Initial CONFIG fixture'
config_pin="$(git -C "$config_src" rev-parse HEAD)"

make_repository "$map_src"
printf 'cmake_minimum_required(VERSION 3.21)\n' > "$map_src/CMakeLists.txt"
git -C "$map_src" -c protocol.file.allow=always submodule add -q \
    "$config_src" external/AOWIS-CONFIG
commit_all "$map_src" 'Pin CONFIG in MAP fixture'

make_repository "$standalone_src"
mkdir -p "$standalone_src/tools"
cp -- "$root/tools/init_map_config_submodule.sh" \
    "$standalone_src/tools/init_map_config_submodule.sh"
git -C "$standalone_src" -c protocol.file.allow=always submodule add -q \
    "$map_src" AOWIS-SERVER-MAP
commit_all "$standalone_src" 'Pin MAP in Standalone fixture'

git clone -q --no-recurse-submodules "$standalone_src" "$checkout"
git -C "$checkout" -c protocol.file.allow=always submodule update \
    --init --checkout -- AOWIS-SERVER-MAP >/dev/null
[[ ! -e "$checkout/AOWIS-SERVER-MAP/external/AOWIS-CONFIG/CMakeLists.txt" ]]

"$checkout/tools/init_map_config_submodule.sh" >/dev/null
[[ -f "$checkout/AOWIS-SERVER-MAP/external/AOWIS-CONFIG/CMakeLists.txt" ]]
[[ "$(git -C "$checkout/AOWIS-SERVER-MAP/external/AOWIS-CONFIG" rev-parse HEAD)" == "$config_pin" ]]
"$checkout/tools/init_map_config_submodule.sh" >/dev/null
[[ "$(git -C "$checkout/AOWIS-SERVER-MAP/external/AOWIS-CONFIG" rev-parse HEAD)" == "$config_pin" ]]

# Deliberately create an invalid MAP commit with .gitmodules but no gitlink.
git -C "$checkout/AOWIS-SERVER-MAP" submodule deinit -f -- external/AOWIS-CONFIG
git -C "$map_src" rm -q --cached external/AOWIS-CONFIG
rm -rf -- "$map_src/external/AOWIS-CONFIG"
commit_all "$map_src" 'Broken MAP fixture (no committed CONFIG pin)'
git -C "$checkout/AOWIS-SERVER-MAP" fetch -q "$map_src" main
new_map_rev="$(git -C "$map_src" rev-parse HEAD)"
git -C "$checkout/AOWIS-SERVER-MAP" checkout -q --detach "$new_map_rev"
if "$checkout/tools/init_map_config_submodule.sh" >"$temporary/error.log" 2>&1; then
    printf 'ERROR: missing MAP CONFIG gitlink was accepted\n' >&2
    exit 1
fi
grep -q 'no committed CONFIG gitlink' "$temporary/error.log"
printf 'PASS: MAP CONFIG pinned checkout, idempotence, missing-gitlink rejection\n'
