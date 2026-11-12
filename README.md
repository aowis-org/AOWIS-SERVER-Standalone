# AOWIS-SERVER-Standalone

Meta-repository for building a standalone version of the AOWIS Controller.

The bundled server components are:

* [AOWIS-SERVER-GUI](https://github.com/aowis-org/AOWIS-SERVER-GUI) (the Controller)
* [AOWIS-SERVER-MAP](https://github.com/aowis-org/AOWIS-SERVER-MAP) (the Caching Map Tile Server)
* [AOWIS-SERVER-DVMDB](https://github.com/aowis-org/AOWIS-SERVER-DVMDB) (embedded native project and hydraulic storage)

## Build

Make sure you have checked out the Git submodules by running either:

* `./git_submodule_init.sh` to initialize the committed submodule versions and their required dependencies.
* `./git_submodule_update.sh` to update the Standalone components and initialize their required dependencies.

Standalone builds **one** AOWIS-CONFIG library, from the GUI's pinned
`AOWIS-SERVER-GUI/external/AOWIS-CONFIG` checkout. Both GUI and embedded MAP
link to that single target. MAP's nested CONFIG checkout is only needed when
building MAP independently; it is not required by Standalone.

### One shared Model build

The GUI is configured before DVMDB. It owns the only `AOWIS::Model` /
`AOWIS::ServerModel` target, located at
`AOWIS-SERVER-GUI/external/AOWIS-SERVER-MODEL`. DVMDB's
`AOWIS_DVMDB_MODEL_SOURCE_DIR` points to this same Model checkout. Its
nested `external/AOWIS-SERVER-MODEL` submodule is **not initialized** by
Standalone, so Model is neither checked out nor compiled twice. If DVMDB's
canonical codec doesn't match the pinned GUI Model version, CMake stops with
an explicit schema error; update the matching submodule revisions together.

DVMDB's native ProjectService, hydraulic codec and bounded HTTP routes are
linked directly into the Standalone GUI. Standalone starts **no external DVMDB
process**. Instead, the GUI owns a single in-process service and catalogue lock
for every configured local DVMDB directory. It exposes a dynamically allocated
`127.0.0.1` endpoint **only inside the running application** and uses the same
validated project and working-copy routes as the standalone DVMDB server. The
ephemeral endpoint is never stored in the database profile. Native sources,
private drafts, network hydration and fenced autosave share this one owner;
opening a second ProjectService on the same directory is forbidden.

In Projects, select a local database and tick **Use as my personal working
database**. The repository role and UUIDv7 are discovered/configured internally,
without any input field. Create a project on that database and select **Edit
network**. The editor initializes a private draft and autosaves supported
hydraulic transactions. Reopening **Edit network** after an application restart
loads the persisted candidate. Saving a draft is not yet a local Commit.

This adapter requires Linux/POSIX DVMDB support; builds without DVMDB retain
their existing project and map functionality. An internal loopback socket is
used for protocol reuse and is accessible to other local processes; it is not
a security boundary or an external server deployment. DVMDB's independent
command-line daemon and benchmark executables are not part of the default
Standalone build. A focused `aowis-standalone-embedded-dvmdb` smoke test
checks identity, role selection, project creation and unborn draft reopening.

The first run of `./git_submodule_init.sh` after applying a ZIP patch registers
the DVMDB gitlink (Git cannot store a gitlink inside a ZIP). Review and commit
`.gitmodules` and `AOWIS-SERVER-DVMDB` in your Standalone Git repository.
Do not run `git submodule update --init --recursive` at the Standalone root if
you want to avoid fetching DVMDB's redundant Model checkout.

### Linux

After that, you can compile the project by running:

    compile_linux.sh

from the project root. Install Qt 6 development packages, OpenSSL development
libraries (`libssl-dev` on Debian/Ubuntu), libtiff, a C++20 compiler, CMake,
Ninja and Python 3. DVMDB is enabled by default on POSIX systems; pass
`-DAOWIS_STANDALONE_WITH_DVMDB=OFF` to CMake for a GUI/MAP-only build.

### Windows / macOS

For cross-compiling from Linux, you can use a Docker-based setup.

The existing GUI/MAP Windows cross-build remains available, but DVMDB is **disabled by default on Windows**: its POSIX `flock`, `mmap`, and filesystem calls need a Windows port. Enabling DVMDB there intentionally raises a CMake error instead of silently creating a broken build. On macOS, DVMDB is **disabled by default**, preserving the existing cross-build: enabling it needs **target-side OpenSSL Crypto** development libraries, which the current Dockerfile does not provision. The previous Intel-mac-only limitation still applies. A complete macOS/DVMDB cross-build is not yet verified.

#### Prepare the Docker Container

Run:

* Windows: `tools/qt-windows/docker_build.sh`
* macOS: `tools/qt-macos/docker_build.sh`

This will pull a Docker container and install the required additional Qt dependencies inside it.

#### Build for Windows / macOS using the prepared Docker Container

After you have prepared the Docker container, run:

* Windows: `compile_windows.sh`
* macOS: `compile_macos.sh`

from the project root to build AOWIS-SERVER-Standalone for Windows or macOS.

The build results can be found in:

* Windows: `build-windows-dist/`
* macOS: `build-macos-dist/`

These directories should also contain zip files ready for distribution.

### WebAssembly

While [AOWIS-SERVER-GUI](https://github.com/aowis-org/AOWIS-SERVER-GUI) can be built for WebAssembly, this standalone version cannot, because most of the bundled server components have dependencies and requirements that are not compatible with WebAssembly. For example, the tile server caches map tiles to the filesystem to reduce internet traffic, which is important for AOWIS deployments in regions with limited or expensive internet connectivity.
If you want to use the GUI in the browser, you need to set up and use the full server infrastructure instead.
