#!/usr/bin/env bash
set -euo pipefail

# MAP owns CONFIG. Initialize the nested checkout at MAP's *committed* pin,
# not at CONFIG's remote HEAD. Run from any working directory.
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
map_dir="$project_root/AOWIS-SERVER-MAP"
config_path='external/AOWIS-CONFIG'

if [[ ! -f "$map_dir/CMakeLists.txt" ]]; then
    printf 'AOWIS-SERVER-MAP is not initialized. Run ./git_submodule_init.sh first.\n' >&2
    exit 1
fi
if ! git -C "$map_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'AOWIS-SERVER-MAP must be a Git submodule checkout to resolve its CONFIG pin.\n' >&2
    exit 1
fi

# .gitmodules alone does not register a submodule: a committed gitlink is
# necessary so all Standalone clones resolve the same CONFIG revision.
map_pin="$(git -C "$map_dir" ls-tree HEAD -- "$config_path")"
if [[ "$map_pin" != '160000 commit '* ]]; then
    printf 'AOWIS-SERVER-MAP revision %s has no committed CONFIG gitlink (mode 160000).\n' \
        "$(git -C "$map_dir" rev-parse --short HEAD)" >&2
    printf 'Fix the MAP repository first: register external/AOWIS-CONFIG with\n' >&2
    printf '  ./git_submodule_init.sh\n' >&2
    printf 'then commit and push its .gitmodules and CONFIG gitlink in MAP,\n' >&2
    printf 'and update the Standalone MAP gitlink. Do not use a floating CONFIG HEAD.\n' >&2
    exit 1
fi

# Never use --remote here: MAP controls the exact revision that is compatible
# with its configuration API. Only CONFIG is initialized, not unrelated trees.
git -C "$map_dir" submodule sync -- "$config_path"
git -C "$map_dir" submodule update --init --checkout -- "$config_path"
if [[ ! -f "$map_dir/$config_path/CMakeLists.txt" ]]; then
    printf 'MAP CONFIG checkout is incomplete: %s\n' "$map_dir/$config_path" >&2
    exit 1
fi

printf 'MAP CONFIG ready at %s\n' \
    "$(git -C "$map_dir/$config_path" rev-parse --short HEAD)"
