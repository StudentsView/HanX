#!/usr/bin/env python3
"""Stage release CLI and its non-glibc runtime libraries on native Linux."""
import pathlib, re, shutil, subprocess, sys
binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/hanx').resolve()
out = pathlib.Path('build/platform/cli')
out.mkdir(parents=True, exist_ok=True)
shutil.copy2(binary, out / 'hanx-engine')
libs = out / 'lib'
libs.mkdir(exist_ok=True)
result = subprocess.run(['ldd', str(binary)], text=True, capture_output=True, check=True).stdout
if 'not found' in result:
    raise SystemExit('Unresolved runtime libraries:\n' + result)
# glibc and its loader must remain supplied by the host distribution.
system = re.compile(r'^(libc\.|libm\.|libdl\.|libpthread\.|librt\.|libresolv\.|ld-linux)')
for line in result.splitlines():
    match = re.search(r'=>\s+(/\S+)', line)
    if match:
        source = pathlib.Path(match.group(1))
        if not system.match(source.name):
            shutil.copy2(source, libs / source.name)
(out / 'hanx').write_text('''#!/bin/sh
cli_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$cli_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$cli_dir/hanx-engine" "$@"
''')
(out / 'hanx').chmod(0o755)
for file in ['LICENSE','NOTICE']:
    shutil.copy2(file, out / file)
