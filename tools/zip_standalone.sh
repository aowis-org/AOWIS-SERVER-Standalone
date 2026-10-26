#!/usr/bin/env bash
set -euo pipefail

# Snapshot ONLY files belonging to the Standalone superproject itself.
# Git submodules (and everything under their worktrees) are deliberately
# excluded. The submodules need not be initialized for this script to work.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
project_parent="$(dirname -- "$project_root")"
project_name="$(basename -- "$project_root")"

if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [output.zip]\n' "${0##*/}" >&2
    exit 2
fi
for tool in git zip mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Error: required tool is not installed: %s\n' "$tool" >&2
        exit 1
    }
done
if [[ "$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null)" != "$project_root" ]]; then
    printf 'Error: %s must be the root of a Git worktree.\n' "$project_root" >&2
    exit 1
fi

output_arg="${1:-$project_parent/standalone.zip}"
output_dir="$(dirname -- "$output_arg")"
if [[ ! -d "$output_dir" ]]; then
    printf 'Error: output directory does not exist: %s\n' "$output_dir" >&2
    exit 1
fi
output_path="$(cd -- "$output_dir" && pwd -P)/$(basename -- "$output_arg")"
if [[ "$output_path" != *.zip ]]; then
    printf 'Error: output filename must end in .zip.\n' >&2
    exit 1
fi

# Build in a temporary location so failed builds never replace an older ZIP.
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
tmp_archive="$tmp_dir/standalone.zip"

# Gitlinks in the superproject index identify submodule boundaries. Read them
# even if their checkouts are missing; never enumerate their contents.
submodules=()
git -C "$project_root" ls-files --stage -z > "$tmp_dir/gitlinks"
while IFS= read -r -d '' entry; do
    metadata="${entry%%$'\t'*}"
    [[ "${metadata%% *}" == 160000 ]] || continue
    submodules+=("${entry#*$'\t'}")
done < "$tmp_dir/gitlinks"

# Include modified tracked and non-ignored untracked Standalone files, not just
# files committed to HEAD. Files in submodules are explicitly skipped.
files=()
git -C "$project_root" ls-files -z --cached --others --exclude-standard > "$tmp_dir/files"
while IFS= read -r -d '' relative_path; do
    [[ -f "$project_root/$relative_path" || -L "$project_root/$relative_path" ]] || continue
    skip=false
    for submodule in "${submodules[@]}"; do
        if [[ "$relative_path" == "$submodule" || "$relative_path" == "$submodule/"* ]]; then
            skip=true
            break
        fi
    done
    [[ "$skip" == false ]] || continue

    # Do not bundle credentials or machine-local environment files.
    case "/$relative_path" in
        */.env|*/.env.*|*.pem|*.key|*.p12|*.pfx) continue ;;
    esac
    if [[ "$relative_path" == *$'\n'* || "$relative_path" == *$'\r'* ]]; then
        printf 'Error: filenames containing newlines or carriage returns cannot be archived.\n' >&2
        exit 1
    fi
    [[ "$project_root/$relative_path" != "$output_path" ]] || continue
    files+=("$project_name/$relative_path")
done < "$tmp_dir/files"

if [[ ${#files[@]} -eq 0 ]]; then
    printf 'Error: no Standalone files found to archive.\n' >&2
    exit 1
fi

(
    cd -- "$project_parent"
    # -y stores symlinks themselves, never their target contents.
    printf '%s\n' "${files[@]}" | zip -q -y "$tmp_archive" -@
)
mv -f -- "$tmp_archive" "$output_path"
printf 'Created %s (%d Standalone files; no submodules).\n' "$output_path" "${#files[@]}"
