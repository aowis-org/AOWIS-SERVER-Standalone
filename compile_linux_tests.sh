#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
    cat <<'USAGE'
Usage: ./compile_linux_tests.sh [--debug | --release | --both]

  (no option)  Build and test in build-linux-tests (existing build type).
  --debug      Use the independent build-linux-tests-debug directory.
  --release    Use the independent build-linux-tests-release directory.
  --both       Build and test Debug and Release; fail if either fails.

Builds the complete Standalone GUI, GUI/Render test executables, MAP library
suite, and the embedded-DVMDB Standalone smoke test (when DVMDB is enabled).
Runs the AOWIS-labelled CTest suite only after every test target has built.
The DVMDB daemon suite and MAP REST-server tests remain in their own repos.

Environment:
  AOWIS_LINUX_LINKER  lld (default) or system
USAGE
}

case "${1:-}" in
    ''|--debug|--release|--both)
        if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
        ;;
    --help|-h)
        if [[ $# -ne 1 ]]; then usage >&2; exit 2; fi
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

# Use the same pinned linker selection and CTest preflight as AOWIS-GUI,
# rather than maintaining duplicate implementations in the meta-repository.
GUI_TOOLS="${PROJECT_DIR}/AOWIS-SERVER-GUI/tools"
if [[ ! -f "${GUI_TOOLS}/linux_linker.sh" ||
      ! -f "${GUI_TOOLS}/ctest_preflight.py" ]]; then
    printf 'ERROR: GUI test tooling is missing; initialize the GUI submodule first.\n' >&2
    exit 1
fi
source "${GUI_TOOLS}/linux_linker.sh"
LINKER_FLAGS="$(aowis_linux_executable_linker_flags)"

# Match compile_linux.sh: Standalone must share GUI's pinned CONFIG checkout,
# never silently initialize or build MAP's second CONFIG copy.
if [[ ! -f "${PROJECT_DIR}/AOWIS-SERVER-GUI/external/AOWIS-CONFIG/CMakeLists.txt" ]]; then
    (cd -- "${PROJECT_DIR}/AOWIS-SERVER-GUI" && bash ./git_submodule_init.sh --config)
fi

run_suite() {
    local build_dir="$1"
    local build_type="$2"
    local -a cmake_args=(
        -S "${PROJECT_DIR}"
        -B "${build_dir}"
        -G Ninja
        -DBUILD_TESTING=ON
        -DCMAKE_COLOR_DIAGNOSTICS=ON
        "-DCMAKE_EXE_LINKER_FLAGS=${LINKER_FLAGS}"
    )
    if [[ -n "${build_type}" ]]; then
        cmake_args+=("-DCMAKE_BUILD_TYPE=${build_type}")
    fi

    printf '=== Standalone AOWIS tests: %s ===\n' "${build_type:-existing configuration}"
    if ! cmake "${cmake_args[@]}"; then
        printf 'ERROR: Standalone test configuration failed; no tests were run.\n' >&2
        return 1
    fi

    # Unlike compile_linux.sh, this must link ALL test binaries and the GUI
    # before CTest runs. Otherwise CTest can silently execute a stale binary.
    if ! cmake --build "${build_dir}" --target aowis-standalone-tests --parallel; then
        printf 'ERROR: Standalone or test build failed; no tests were run.\n' >&2
        return 1
    fi

    if ! python3 "${GUI_TOOLS}/ctest_preflight.py" "${build_dir}"; then
        printf 'ERROR: Test preflight failed; no tests were run.\n' >&2
        return 1
    fi

    ctest --test-dir "${build_dir}" --output-on-failure -L '^aowis$'
}

case "${1:-}" in
    '') run_suite "${PROJECT_DIR}/build-linux-tests" '' ;;
    --debug) run_suite "${PROJECT_DIR}/build-linux-tests-debug" Debug ;;
    --release) run_suite "${PROJECT_DIR}/build-linux-tests-release" Release ;;
    --both)
        run_suite "${PROJECT_DIR}/build-linux-tests-debug" Debug
        run_suite "${PROJECT_DIR}/build-linux-tests-release" Release
        ;;
esac
