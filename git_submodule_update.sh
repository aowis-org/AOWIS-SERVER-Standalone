#!/bin/bash

#git submodule update --recursive --remote

git pull origin main
git submodule sync --recursive
git submodule update --init --recursive

git status

