#!/bin/bash
# Flutter Linux build - Nix/IDX ortaminda PKG_CONFIG_PATH gerekebilir.
# Kullanim: ./run_linux.sh   veya   bash run_linux.sh
set -e
cd "$(dirname "$0")"
if [ -z "$PKG_CONFIG_PATH" ] && command -v pkg-config >/dev/null 2>&1; then
  PC_DIRS=""
  for dir in /nix/store/*/lib/pkgconfig; do
    [ -d "$dir" ] || continue
    [ -f "$dir/gtk+-3.0.pc" ] || [ -f "$dir/glib-2.0.pc" ] || continue
    PC_DIRS="${PC_DIRS:+$PC_DIRS:}$dir"
  done
  [ -n "$PC_DIRS" ] && export PKG_CONFIG_PATH="$PC_DIRS"
fi
flutter pub get
exec flutter run -d linux "$@"
