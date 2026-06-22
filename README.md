# AOWIS-SERVER-Standalone

Meta-repository to compile a standalone version of the **AOWIS Controller**.

The baked-in server components are:

- [AOWIS-SERVER-GUI](https://github.com/aowis-org/AOWIS-SERVER-GUI) (the *Controller*)
- [AOWIS-SERVER-MAP](https://github.com/aowis-org/AOWIS-SERVER-MAP) (the *Caching Map Tile Server*)

## Build

Make sure you have also checked out the Git submodules by running either

* `git submodule update --init --recursive` (shortcut: `git_submodule_init.sh`) or
* `git submodule update --recursive --remote` (shortcut: `git_submodule_update.sh`)

### Linux
After that, you can compile by running

- `compile_linux.sh`

### WebAssembly
While the [AOWIS-SERVER-GUI](https://github.com/aowis-org/AOWIS-SERVER-GUI) can be built for WebAssembly, this standalone version cannot, because most of the server components baked in have dependencies and requirements that do not work with WebAssembly (e.g. the tileserver caches map tiles to filesystem). If you want to use the GUI in the browser, you have to use the full server infrastructure.
