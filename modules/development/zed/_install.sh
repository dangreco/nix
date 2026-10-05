# shellcheck shell=bash
# Adapted from Zed's official installer (https://zed.dev/install.sh, retrieved
# 2026-10): Linux, stable channel only. Downloads the release tarball and unpacks
# it into ~/.local (tarball contains zed.app/), links ~/.local/bin/zed, and
# installs the .desktop entry with absolute paths. ZED_BUNDLE_PATH installs from
# a local tarball instead of downloading (offline/testing).
set -eu

arch="$(uname -m)"
case "$arch" in
    x86_64 | amd64) arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

temp="$(mktemp -d "${TMPDIR:-/tmp}/zed-install-XXXXXX")"
trap 'rm -rf "$temp"' EXIT

if [ -n "${ZED_BUNDLE_PATH:-}" ]; then
    cp "$ZED_BUNDLE_PATH" "$temp/zed-linux-$arch.tar.gz"
else
    curl -fL "https://cloud.zed.dev/releases/stable/latest/download?asset=zed&arch=$arch&os=linux&source=install.sh" \
        -o "$temp/zed-linux-$arch.tar.gz"
fi

mkdir -p "$HOME/.local/zed.app" "$HOME/.local/bin" "$HOME/.local/share/applications"
# Upstream removes ~/.local/zed.app outright; on impermanence hosts that path is
# a bind mount, so clear its contents instead of the mount point itself.
find "$HOME/.local/zed.app" -mindepth 1 -delete
tar -xzf "$temp/zed-linux-$arch.tar.gz" -C "$HOME/.local/"
ln -sf "$HOME/.local/zed.app/bin/zed" "$HOME/.local/bin/zed"

desktop="$HOME/.local/share/applications/dev.zed.Zed.desktop"
cp "$HOME/.local/zed.app/share/applications/dev.zed.Zed.desktop" "$desktop"
sed -i "s|Icon=zed|Icon=$HOME/.local/zed.app/share/icons/hicolor/512x512/apps/zed.png|g" "$desktop"
sed -i "s|Exec=zed|Exec=$HOME/.local/zed.app/bin/zed|g" "$desktop"
