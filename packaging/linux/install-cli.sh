#!/bin/sh
# HanX per-user installer. GUI includes its own engine; terminal exposure is optional.
set -eu
prefix=${HOME}/.local
components=
yes=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --components) [ "$#" -gt 1 ] || { echo 'Missing --components value' >&2; exit 1; }; components=$2; shift 2 ;;
    --components=*) components=${1#*=}; shift ;;
    --prefix) [ "$#" -gt 1 ] || exit 1; prefix=$2; shift 2 ;;
    --yes) yes=1; shift ;;
    --help) echo 'Usage: ./install-cli.sh [--components cli|gui|all] [--prefix DIR] [--yes]'; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) prefix=$1; shift ;;
  esac
done
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "$components" ] && [ "$yes" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
  # stty is restored on every exit, including Ctrl-C and termination.
  saved_tty=$(stty -g)
  restore_tty() { stty "$saved_tty"; printf '\033[?25h'; }
  trap 'restore_tty' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  stty -echo -icanon min 1 time 0
  printf '\033[?25l'
  selected=0
  while :; do
    printf '\r\033[JChoose HanX components (arrows, Enter; q cancels)\n'
    i=0
    for label in 'CLI only — terminal commands' 'GUI only — desktop app, internal engine' 'GUI + CLI — desktop and terminal commands'; do
      mark=' '; [ "$selected" -ne "$i" ] || mark='>'
      printf '%s %s\n' "$mark" "$label"
      i=$((i + 1))
    done
    printf '\033[4A'
    key=$(dd bs=1 count=1 2>/dev/null) || exit 1
    case "$key" in
      '') case "$selected" in 0) components=cli;; 1) components=gui;; 2) components=all;; esac; break ;;
      q|Q) echo 'Setup cancelled.'; exit 130 ;;
      "$(printf '\033')")
        # Read complete CSI arrow sequences; q is the explicit cancel key.
        stty min 0 time 2
        rest=$(dd bs=1 count=2 2>/dev/null) || exit 1
        stty min 1 time 0
        [ -n "$rest" ] || { echo "Setup cancelled."; exit 130; }
        case "$rest" in '[A') selected=$(((selected + 2) % 3));; '[B') selected=$(((selected + 1) % 3));; esac ;;
    esac
  done
  printf '\r\033[J'; restore_tty; trap - EXIT INT TERM HUP
fi
components=${components:-cli}
case "$components" in cli|gui|all) ;; *) echo 'Components must be cli, gui, or all.' >&2; exit 1;; esac
mkdir -p "$prefix"
prefix=$(CDPATH= cd -- "$prefix" && pwd)
target="$prefix/lib/hanx"
# Check every selected destination before changing anything.
if [ "$components" = cli ] || [ "$components" = all ]; then
  for entry in "$target" "$prefix/bin/hanx" "$prefix/bin/hanx-cli"; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then echo "Refusing to overwrite existing installation: $entry" >&2; exit 1; fi
  done
  [ -x "$source_dir/hanx" ] && [ -x "$source_dir/hanx-engine" ] || { echo 'Extract the complete native CLI archive before installing.' >&2; exit 1; }
fi
if [ "$components" = gui ] || [ "$components" = all ]; then
  # This helper downloads and verifies the release AppImage, with no root actions.
  "$source_dir/install-gui.sh" --prefix "$prefix" --yes
fi
if [ "$components" = cli ] || [ "$components" = all ]; then
  mkdir -p "$prefix/lib" "$prefix/bin"
  cp -R "$source_dir" "$target"
  ln -s "$target/hanx" "$prefix/bin/hanx"
  ln -s "$target/hanx" "$prefix/bin/hanx-cli"
  printf 'Installed terminal commands. Add %s/bin to PATH if needed.\n' "$prefix"
  printf 'Uninstall: remove %s/bin/hanx, %s/bin/hanx-cli and %s\n' "$prefix" "$prefix" "$target"
else
  printf 'GUI only selected. No terminal commands were added.\n'
fi
printf 'PDF export: an optional compatible local renderer is required; nothing was installed automatically.\n'
printf 'Debian/Ubuntu users may choose: sudo apt-get install libreoffice\n'
