cmake_minimum_required(VERSION 3.22)

project(AOWIS-SERVER-Standalone LANGUAGES CXX)

# GUI, MODEL, MAP, and DVMDB all use C++20.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(AOWIS_STANDALONE_BUILD ON CACHE BOOL "Build AOWIS standalone GUI")

# Only the map core library is needed; don't build its REST server executable.
set(AOWIS_SERVER_MAP_BUILD_SERVER OFF CACHE BOOL
    "Build AOWIS map REST server executable" FORCE)

# DVMDB's storage layer uses POSIX APIs (flock, mmap, fsync, etc.), so it
# cannot currently be cross-compiled as-is for Windows/MinGW.
if(WIN32 OR APPLE)
    # Keep existing Windows/macOS cross-builds working until native DVMDB
    # and target-side OpenSSL have been qualified with those toolchains.
    set(_aowis_dvmdb_default OFF)
else()
    set(_aowis_dvmdb_default ON)
endif()
option(AOWIS_STANDALONE_WITH_DVMDB
    "Build and link the DVMDB embedded storage/model libraries"
    ${_aowis_dvmdb_default})
if(AOWIS_STANDALONE_WITH_DVMDB AND WIN32)
    message(FATAL_ERROR
        "AOWIS-SERVER-DVMDB currently requires POSIX filesystem APIs and "
        "cannot be built for Windows. Use -DAOWIS_STANDALONE_WITH_DVMDB=OFF "
        "for the GUI/MAP-only Windows build.")
endif()

add_subdirectory(AOWIS-SERVER-MAP)

# GUI owns the *only* Model CMake target. DVMDB must be added afterwards:
# its CMakeLists.txt reuses AOWIS::Model if it already exists.
add_subdirectory(AOWIS-SERVER-GUI)
if(NOT TARGET AOWIS::Model OR NOT TARGET AOWIS::ServerModel)
    message(FATAL_ERROR "GUI did not provide the shared AOWIS Model target")
endif()

target_compile_definitions(aowis-server-gui PRIVATE AOWIS_STANDALONE)
target_link_libraries(aowis-server-gui PRIVATE aowis-server-map-core)

if(AOWIS_STANDALONE_WITH_DVMDB)
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/AOWIS-SERVER-DVMDB/CMakeLists.txt")
        message(FATAL_ERROR
            "DVMDB submodule is missing. Run ./git_submodule_init.sh")
    endif()

    # Point DVMDB's codec generator at GUI's pinned Model source tree as well.
    # Its own nested Model submodule is deliberately not checked out/built.
    # A schema mismatch will fail configuration rather than silently mixing
    # two different Model revisions.
    set(AOWIS_DVMDB_MODEL_SOURCE_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/AOWIS-SERVER-GUI/external/AOWIS-SERVER-MODEL"
        CACHE PATH "Shared GUI Model source for DVMDB codec" FORCE)
    set(AOWIS_DVMDB_WITH_MODEL_CODEC ON CACHE BOOL
        "Build DVMDB's canonical Model codec" FORCE)
    # Use the same bounded, tested working-copy routes in a process-owned
    # loopback transport; do not launch the standalone DVMDB daemon.
    set(AOWIS_DVMDB_WITH_HTTP_SERVER ON CACHE BOOL
        "Build DVMDB HTTP transport library" FORCE)

    # DVMDB has an extensive independent test suite. Do not register/build it
    # as part of the normal Standalone GUI build; the GUI/MAP test setting is
    # kept unchanged, and DVMDB can be tested independently in its own repo.
    set(_aowis_saved_build_testing "${BUILD_TESTING}")
    set(BUILD_TESTING OFF)
    add_subdirectory(AOWIS-SERVER-DVMDB EXCLUDE_FROM_ALL)
    set(BUILD_TESTING "${_aowis_saved_build_testing}")
    unset(_aowis_saved_build_testing)

    if(NOT TARGET AOWIS::DvmdbProjectService OR NOT TARGET AOWIS::DvmdbHydraulic)
        message(FATAL_ERROR "DVMDB native project/hydraulic targets were not created")
    endif()
    # The in-process HTTP adapter shares the same native Model and DVMDB
    # service, so Standalone needs no separately started database daemon.
    target_sources(aowis-server-gui PRIVATE
        AOWIS-SERVER-GUI/src/projects/embedded_dvmdb_host.cpp)
    target_link_libraries(aowis-server-gui PRIVATE
        AOWIS::DvmdbProjectService
        AOWIS::DvmdbHydraulic
        aowis-dvmdb-http)
    target_compile_definitions(aowis-server-gui PRIVATE AOWIS_STANDALONE_DVMDB_ENABLED)
    if(BUILD_TESTING)
        # Qt imported targets created in GUI's subdirectory are scoped there;
        # the Standalone-level smoke-test target needs its own Qt import.
        find_package(Qt6 REQUIRED COMPONENTS Core)
        add_executable(aowis-standalone-embedded-dvmdb-tests
            tests/embedded_dvmdb_host_tests.cpp
            AOWIS-SERVER-GUI/src/projects/embedded_dvmdb_host.cpp)
        target_include_directories(aowis-standalone-embedded-dvmdb-tests PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/AOWIS-SERVER-GUI/src")
        target_compile_definitions(aowis-standalone-embedded-dvmdb-tests PRIVATE
            AOWIS_STANDALONE_DVMDB_ENABLED)
        target_link_libraries(aowis-standalone-embedded-dvmdb-tests PRIVATE
            aowis-dvmdb-http Qt6::Core)
        add_test(NAME aowis-standalone-embedded-dvmdb
            COMMAND aowis-standalone-embedded-dvmdb-tests)
        set_tests_properties(aowis-standalone-embedded-dvmdb PROPERTIES
            LABELS "aowis;standalone;working-copy" TIMEOUT 30)
    endif()
    message(STATUS "Standalone DVMDB enabled: shared GUI Model target (single build)")
elseif(WIN32)
    message(STATUS "Standalone DVMDB disabled for Windows (POSIX-only engine)")
elseif(APPLE)
    message(STATUS "Standalone DVMDB disabled for macOS by default (target OpenSSL not provisioned)")
endif()
