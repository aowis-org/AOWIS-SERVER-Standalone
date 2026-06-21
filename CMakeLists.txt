
cmake_minimum_required(VERSION 3.16)

project(AOWIS-SERVER-Standalone LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(AOWIS_STANDALONE_BUILD ON CACHE BOOL "Build AOWIS standalone GUI")

# We only need the map core library, not the standalone map REST server executable.
set(AOWIS_SERVER_MAP_BUILD_SERVER OFF CACHE BOOL "Build AOWIS map REST server executable" FORCE)

add_subdirectory(AOWIS-SERVER-MAP)
add_subdirectory(AOWIS-SERVER-GUI)

target_compile_definitions(aowis-server-gui
    PRIVATE
        AOWIS_STANDALONE
)

target_link_libraries(aowis-server-gui
    PRIVATE
        aowis-server-map-core
)
