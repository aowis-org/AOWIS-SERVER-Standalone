#!/bin/bash

cmake -S . -B build-linux -G Ninja -DCMAKE_COLOR_DIAGNOSTICS=ON
cmake --build build-linux --parallel

./build-linux/AOWIS-SERVER-GUI/aowis-server-gui
