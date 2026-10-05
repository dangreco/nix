#!/usr/bin/env bash
# Adapted from OMP's official installer: https://omp.sh/install.sh
# Linux, prebuilt binary only. Downloads the release binary into ~/.local/bin/omp
set -eu

export PI_INSTALL_DIR="$HOME/.local/bin"
curl -fsSL https://omp.sh/install.sh | sh -s -- --binary
