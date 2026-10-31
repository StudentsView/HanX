#!/bin/sh
set -e
# Package managers must never read terminal input or silently expose CLI commands.
printf 'HanX desktop installed with its internal document engine.\n'
printf 'To install terminal commands too, use the standalone CLI archive install-cli.sh wizard.\n'
printf 'PDF export can require a compatible local renderer; install one only if you choose.\n'
