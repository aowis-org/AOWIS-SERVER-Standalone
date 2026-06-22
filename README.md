# AOWIS-SERVER-Standalone

Meta-repository for building a standalone version of the **AOWIS Controller**.

The bundled server components are:

- [AOWIS-SERVER-GUI](https://github.com/aowis-org/AOWIS-SERVER-GUI) (the *Controller*)
- [AOWIS-SERVER-MAP](https://github.com/aowis-org/AOWIS-SERVER-MAP) (the *Caching Map Tile Server*)

## Build

Make sure you have checked out the Git submodules by running either:

- `git submodule update --init --recursive` (shortcut: `git_submodule_init.sh`)
- `git submodule update --recursive --remote` (shortcut: `git_submodule_update.sh`)

### Linux

After that, you can compile the project by running:

```bash
compile_linux.sh
```

from the project root. Make sure a suitable Qt 6 environment is installed using your distribution's package manager.

### Windows

For cross-compiling from Linux, you can use a Docker-based setup.

#### Prepare the Docker Container

Run:

```bash
/tools/qt-windows/docker_build.sh
```

This will pull a Docker container and install the required additional Qt dependencies inside it.

#### Build for Windows using the prepared Docker Container

After you have downloaded and prepared the Docker container, as described in the previous section, run:

```bash
compile_windows.sh
```

from the project root to build AOWIS-SERVER-Standalone for Windows.

The build result can be found in:

```bash
build-windows-dist/
```

This directory should also contain a zip file ready for distribution.

### WebAssembly

While [AOWIS-SERVER-GUI](https://github.com/aowis-org/AOWIS-SERVER-GUI) can be built for WebAssembly, this standalone version cannot, because most of the bundled server components have dependencies and requirements that do not work with WebAssembly. For example, the tile server caches map tiles to the filesystem.

If you want to use the GUI in the browser, you need to set up and use the full server infrastructure instead.
