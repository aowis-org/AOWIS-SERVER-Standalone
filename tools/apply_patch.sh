#!/usr/bin/env bash
set -euo pipefail

# Apply a Standalone patch ZIP rooted at the repository directory, then
# regenerate a source snapshot of the Standalone superproject only.
# A patch may replace this script while it runs, so put the entire operation
# in a function that Bash parses before extraction begins.
main() {
    local script_dir project_root project_parent project_name
    local manifest patch_name patch entry relative path segment
    local -a entries=() segments=() submodules=()

    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    project_root="$(cd -- "$script_dir/.." && pwd -P)"
    project_parent="$(dirname -- "$project_root")"
    project_name="$(basename -- "$project_root")"
    manifest="$project_root/.aowis-patch-delete.txt"

    for tool in git realpath; do
        command -v "$tool" >/dev/null 2>&1 || {
            printf 'Required tool is not installed: %s\n' "$tool" >&2
            return 1
        }
    done
    [[ "$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null)" == "$project_root" ]] || {
        printf 'Expected the Standalone Git worktree root: %s\n' "$project_root" >&2
        return 1
    }
    # Exclude Git submodules from Standalone patches as well as snapshots.
    local index_entry index_metadata
    while IFS= read -r -d '' index_entry; do
        index_metadata="${index_entry%%$'\t'*}"
        [[ "${index_metadata%% *}" == 160000 ]] || continue
        submodules+=("${index_entry#*$'\t'}")
    done < <(git -C "$project_root" ls-files --stage -z)

    in_submodule() {
        local check_path="$1" submodule
        for submodule in "${submodules[@]}"; do
            [[ "$check_path" == "$submodule" || "$check_path" == "$submodule/"* ]] && return 0
        done
        return 1
    }

    apply_deletions() {
        [[ ! -L "$manifest" ]] || {
            printf 'Refusing symlinked patch deletion manifest.\n' >&2
            return 1
        }
        [[ -f "$manifest" ]] || return 0

        local relative path segment
        local -a segments=() deletion_paths=()

        # Validate every entry before removing any file. Use realpath so
        # symlinks cannot redirect deletions outside this worktree.
        while IFS= read -r relative || [[ -n "$relative" ]]; do
            [[ -n "$relative" && "$relative" != /* &&
               "$relative" != .* && "$relative" != */ &&
               "$relative" != *'\\'* && "$relative" != *'//'* ]] || {
                printf 'Unsafe patch deletion path: %s\n' "$relative" >&2
                return 1
            }
            IFS='/' read -r -a segments <<< "$relative"
            for segment in "${segments[@]}"; do
                [[ -n "$segment" && "$segment" != . &&
                   "$segment" != .. && "$segment" != .git ]] || {
                    printf 'Unsafe patch deletion path: %s\n' "$relative" >&2
                    return 1
                }
            done
            if in_submodule "$relative"; then
                printf 'Refusing deletion inside submodule: %s\n' "$relative" >&2
                return 1
            fi
            path="$(realpath -m -- "$project_root/$relative")"
            [[ "$path" == "$project_root/"* && ! -d "$path" ]] || {
                printf 'Unsafe patch deletion target: %s\n' "$relative" >&2
                return 1
            }
            deletion_paths+=("$path")
        done < "$manifest"

        for path in "${deletion_paths[@]}"; do
            rm -f -- "$path"
        done
        rm -f -- "$manifest"
        printf 'Removed %d obsolete file(s) listed by patch.\n' "${#deletion_paths[@]}"
    }

    if [[ $# -eq 1 && "$1" == '--finish' ]]; then
        if [[ ! -e "$manifest" && ! -L "$manifest" ]]; then
            printf 'No pending patch deletions.\n'
            return 0
        fi
        apply_deletions
        return
    fi

    if [[ $# -ne 1 ]]; then
        printf 'Usage: %s /path/to/aowis-standalone-<description>.zip | --finish\n' "${0##*/}" >&2
        return 2
    fi
    for tool in unzip touch; do
        command -v "$tool" >/dev/null 2>&1 || {
            printf 'Required tool is not installed: %s\n' "$tool" >&2
            return 1
        }
    done

    patch_name="$(basename -- "$1")"
    # Distinct patch naming prevents accidentally applying DB_CUSTOM or GUI
    # patches to the Standalone meta-repository.
    if [[ "$patch_name" != aowis-standalone-*.zip ||
          "$patch_name" == aowis-standalone-.zip ]]; then
        printf 'Refusing patch %s: expected aowis-standalone-<description>.zip\n' "$patch_name" >&2
        return 1
    fi
    patch="$(realpath -- "$1")"
    [[ -f "$patch" ]] || {
        printf 'Patch is not a file: %s\n' "$patch" >&2
        return 1
    }

    # Reject archives that escape the checkout or overwrite Git metadata.
    # ZIP member paths must have the same root as zip_standalone.sh produces.
    unzip -tqq -- "$patch"
    while IFS= read -r entry; do
        [[ "$entry" == "$project_name/"* &&
           "$entry" != *'\\'* &&
           "$entry" != *$'\r'* &&
           "$entry" != *'/../'* &&
           "$entry" != *'/./'* &&
           "$entry" != *'//'* ]] || {
            printf 'Invalid patch path: %s\n' "$entry" >&2
            return 1
        }
        relative="${entry#"$project_name"/}"
        [[ -n "$relative" ]] || continue
        IFS='/' read -r -a segments <<< "$relative"
        for segment in "${segments[@]}"; do
            [[ "$segment" != .git && "$segment" != .. && "$segment" != . ]] || {
                printf 'Patch attempts to write protected path: %s\n' "$entry" >&2
                return 1
            }
        done
        if in_submodule "$relative"; then
            printf 'Refusing patch entry inside submodule: %s\n' "$entry" >&2
            return 1
        fi
        entries+=("$entry")
    done < <(unzip -Z -1 -- "$patch")
    [[ ${#entries[@]} -gt 0 ]] || {
        printf 'Patch archive has no files.\n' >&2
        return 1
    }

    unzip -q -o -- "$patch" -d "$project_parent"

    # Unzip restores archived mtimes; refresh them so CMake/Ninja reliably
    # notices modified sources even when the ZIP has older timestamps.
    for entry in "${entries[@]}"; do
        touch -c -m -- "$project_parent/$entry"
    done
    apply_deletions
    printf 'Applied %s with fresh file timestamps.\n' "$patch"

    # Snapshot the Standalone superproject only (no submodule contents).
    if ! "$script_dir/zip_standalone.sh"; then
        printf 'Patch was applied, but creating standalone.zip failed.\n' >&2
        return 1
    fi
}

main "$@"
