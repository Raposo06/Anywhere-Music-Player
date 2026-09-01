#!/usr/bin/env bash
#
# Package build/linux/x64/release/bundle into a single-file AppImage.
#
# BEST-EFFORT. This has not been verified on a clean desktop yet. Two known
# soft spots, both from how this app links on Linux (see docs/operations.md):
#
#   1. media_kit dlopen()s libmpv at runtime — it's not in the binary's NEEDED
#      list, so linuxdeploy can't discover it. We copy libmpv.so.2 in by hand
#      and let linuxdeploy chase *its* deps (ffmpeg, libass, ...). If audio is
#      silent in the AppImage but fine from the tarball, a transitive mpv dep
#      didn't get bundled.
#   2. flutter_secure_storage needs a Secret Service provider (gnome-keyring /
#      kwallet) on the host. An AppImage can't ship the daemon; a headless or
#      minimal box will throw on credential load.
#
# The .tar.gz the workflow also produces is the reliable Linux artifact. Fix
# this on an actual Linux desktop, not in a can't-test-here session.
#
# Usage: scripts/package-linux-appimage.sh <version>

set -euo pipefail

VERSION="${1:?usage: package-linux-appimage.sh <version>}"
BUNDLE="build/linux/x64/release/bundle"
APPDIR="build/AppDir"
APPNAME="anywhere-music-player"

[ -d "$BUNDLE" ] || { echo "no bundle at $BUNDLE — run 'flutter build linux --release' first" >&2; exit 1; }

export APPIMAGE_EXTRACT_AND_RUN=1   # CI runners have no FUSE

rm -rf "$APPDIR"
install -d "$APPDIR/usr/bin" "$APPDIR/usr/lib"
cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"

mpv_lib=$(ldconfig -p | awk '/libmpv\.so\.2/ {print $NF; exit}')
[ -n "${mpv_lib:-}" ] || { echo "libmpv.so.2 not found — install mpv/libmpv-dev" >&2; exit 1; }
cp -L "$mpv_lib" "$APPDIR/usr/lib/"

install -Dm644 assets/icons/psx.png "$APPDIR/$APPNAME.png"
cat > "$APPDIR/$APPNAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Anywhere Music Player
Exec=anywhere_music_player
Icon=$APPNAME
Categories=AudioVideo;Audio;Player;
Terminal=false
StartupWMClass=com.anywhere.anywhere_music_player
EOF

curl -sSL -o linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
curl -sSL -o linuxdeploy-plugin-gtk.sh https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy linuxdeploy-plugin-gtk.sh

DEPLOY_GTK_VERSION=3 ./linuxdeploy --appdir "$APPDIR" \
  --plugin gtk \
  --library "$APPDIR/usr/lib/$(basename "$mpv_lib")" \
  --desktop-file "$APPDIR/$APPNAME.desktop" \
  --icon-file "$APPDIR/$APPNAME.png" \
  --custom-apprun <(printf '%s\n' '#!/bin/sh' 'HERE=$(dirname "$(readlink -f "$0")")' 'export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"' 'exec "$HERE/usr/bin/anywhere_music_player" "$@"') \
  --output appimage

mv ./*.AppImage "AnywhereMusicPlayer-$VERSION-x86_64.AppImage"
echo "wrote AnywhereMusicPlayer-$VERSION-x86_64.AppImage"
