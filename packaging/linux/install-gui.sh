#!/bin/sh
# Download a verified AppImage to a per-user location. Never invokes sudo.
set -eu
version=2.9.0
prefix=${HOME}/.local
while [ "$#" -gt 0 ]; do
  case "$1" in --prefix) prefix=$2; shift 2;; --yes) shift;; *) echo "Unknown option: $1" >&2; exit 1;; esac
done
case "$(uname -m)" in x86_64) arch=x64;; aarch64|arm64) arch=arm64;; *) echo 'No HanX GUI build for this architecture.' >&2; exit 1;; esac
asset="HanX-${version}-linux-${arch}.AppImage"
base="https://github.com/StudentsView/HanX/releases/download/v${version}"
target="$prefix/lib/hanx-gui/$version/$asset"
desktop="$prefix/share/applications/hanx.desktop"
for entry in "$target" "$desktop"; do [ ! -e "$entry" ] && [ ! -L "$entry" ] || { echo "Refusing to overwrite: $entry" >&2; exit 1; }; done
command -v curl >/dev/null || { echo 'Install curl, then run this installer again.' >&2; exit 1; }
command -v sha256sum >/dev/null || { echo 'Install sha256sum (coreutils), then retry.' >&2; exit 1; }
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
curl --fail --location --proto '=https' --tlsv1.2 --max-time 60 "$base/SHA256SUMS" -o "$temporary/SHA256SUMS"
hash=$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "$temporary/SHA256SUMS")
[ "${#hash}" -eq 64 ] && ! printf '%s' "$hash" | LC_ALL=C grep -q '[^0-9a-fA-F]' || { echo 'Missing or malformed release SHA256 checksum.' >&2; exit 1; }
curl --fail --location --proto '=https' --tlsv1.2 --max-time 600 "$base/$asset" -o "$temporary/$asset"
printf '%s  %s\n' "$hash" "$temporary/$asset" | sha256sum --check --status || { echo 'Checksum mismatch; nothing was installed.' >&2; exit 1; }
mkdir -p "$(dirname -- "$target")" "$(dirname -- "$desktop")"
# noclobber guards against a second installer creating the same destination.
(set -C; cat "$temporary/$asset" > "$target")
chmod 755 "$target"
# Desktop Exec uses quoted paths, escaping characters meaningful to the desktop launcher.
escaped=$(printf '%s' "$target" | sed 's/[\\"`$]/\\&/g')
(set -C; printf '[Desktop Entry]\nType=Application\nName=HanX\nComment=Local document editor\nExec="%s" %%F\nTerminal=false\nCategories=Office;\n' "$escaped" > "$desktop")
printf 'Installed GUI: %s\nLaunch from your application menu.\n' "$target"
printf 'If AppImage reports a FUSE runtime issue, install your distribution’s libfuse2 package explicitly or choose the .deb release.\n'
printf 'Uninstall: remove %s and %s\n' "$target" "$desktop"
