#!/bin/sh
# Install only the standalone CLI and docs. This does not build a pkg or change HanX.app.
set -eu
hw_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
hw_prefix="$HOME/Library/Application Support/HanX/CLI/2.9.0"
hw_bin_dir="$HOME/.local/bin"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix) [ "$#" -ge 2 ] || exit 2; hw_prefix=$2; shift 2 ;;
    --bin-dir) [ "$#" -ge 2 ] || exit 2; hw_bin_dir=$2; shift 2 ;;
    --help) printf '%s\n' 'install-cli.sh [--prefix ABSOLUTE_DIRECTORY] [--bin-dir ABSOLUTE_DIRECTORY]'; exit 0 ;;
    *) printf '%s\n' "Unknown installer option: $1" >&2; exit 2 ;;
  esac
done
case "$hw_prefix" in /*) ;; *) printf '%s\n' 'prefix must be absolute' >&2; exit 2 ;; esac
case "$hw_bin_dir" in /*) ;; *) printf '%s\n' 'bin-dir must be absolute' >&2; exit 2 ;; esac
hw_binary="$hw_root/hanx"
[ -f "$hw_binary" ] || hw_binary="$hw_root/build/hanx-cli"
[ -x "$hw_binary" ] || { printf '%s\n' 'Build the CLI first with ./build-cli.sh --universal' >&2; exit 1; }
# Never replace unrelated commands or an unrecognized directory.
for hw_name in hanx hanx-cli; do
  hw_target="$hw_bin_dir/$hw_name"
  if [ -e "$hw_target" ] || [ -L "$hw_target" ]; then
    [ -L "$hw_target" ] || { printf '%s\n' "Existing command is not a symlink: $hw_target" >&2; exit 1; }
    hw_old=$(readlink "$hw_target")
    case "$hw_old" in /*) hw_resolved=$hw_old ;; *) hw_resolved="$hw_bin_dir/$hw_old" ;; esac
    hw_old_parent=$(dirname -- "$hw_resolved")
    if [ "$(basename -- "$hw_resolved")" != "hanx" ] || [ ! -f "$hw_old_parent/HANX-CLI-VERSION" ]; then
      printf '%s\n' "Command belongs to another installation: $hw_target" >&2
      exit 1
    fi
  fi
done
if [ -e "$hw_prefix" ] && [ ! -f "$hw_prefix/HANX-CLI-VERSION" ]; then
  printf '%s\n' "Refusing to replace unrecognized directory: $hw_prefix" >&2; exit 1
fi
hw_parent=$(dirname -- "$hw_prefix")
mkdir -p "$hw_parent" "$hw_bin_dir"
hw_stage=$(mktemp -d "$hw_parent/.hanx-cli-stage.XXXXXX")
hw_backup=''
trap 'if [ -n "$hw_stage" ] && [ -d "$hw_stage" ]; then rm -rf -- "$hw_stage"; fi' EXIT HUP INT TERM
cp -p "$hw_binary" "$hw_stage/hanx"
chmod 755 "$hw_stage/hanx"
if [ -f "$hw_root/docs/cli/README.md" ]; then
  cp "$hw_root/docs/cli/README.md" "$hw_stage/README.md"
  cp -R "$hw_root/docs/cli/examples" "$hw_stage/examples"
else
  cp "$hw_root/README.md" "$hw_stage/README.md"
  cp -R "$hw_root/examples" "$hw_stage/examples"
fi
printf '%s\n' '2.9.0' > "$hw_stage/HANX-CLI-VERSION"
"$hw_stage/hanx" --version >/dev/null
if [ -e "$hw_prefix" ]; then
  hw_backup=$(mktemp -d "$hw_parent/.hanx-cli-backup.XXXXXX")
  mv "$hw_prefix" "$hw_backup/CLI"
fi
if ! mv "$hw_stage" "$hw_prefix"; then
  if [ -n "$hw_backup" ]; then mv "$hw_backup/CLI" "$hw_prefix"; fi
  exit 1
fi
hw_stage=''
ln -sfn "$hw_prefix/hanx" "$hw_bin_dir/hanx"
ln -sfn "$hw_prefix/hanx" "$hw_bin_dir/hanx-cli"
printf '%s\n' "Installed: $hw_prefix/hanx" "Command: $hw_bin_dir/hanx" "MCP: $hw_bin_dir/hanx mcp"
