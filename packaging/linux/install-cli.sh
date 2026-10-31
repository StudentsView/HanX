#!/bin/sh
# Run from an extracted HanX CLI archive; optional argument is installation prefix.
set -eu
prefix=${1:-"$HOME/.local"}
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$prefix"
prefix=$(CDPATH= cd -- "$prefix" && pwd)
target="$prefix/lib/hanx"
if [ -e "$target" ] || [ -L "$prefix/bin/hanx" ] || [ -e "$prefix/bin/hanx" ]; then
  echo "Refusing to overwrite an existing HanX installation: $target or $prefix/bin/hanx" >&2
  exit 1
fi
[ -x "$source_dir/hanx" ] && [ -x "$source_dir/hanx-engine" ] || { echo 'Extract the complete CLI archive before installing.' >&2; exit 1; }
mkdir -p "$prefix/lib" "$prefix/bin"
cp -R "$source_dir" "$target"
ln -s "$target/hanx" "$prefix/bin/hanx"
printf 'Installed HanX. Add %s/bin to PATH if needed.\nUninstall: remove %s/bin/hanx and %s\n' "$prefix" "$prefix" "$target"
