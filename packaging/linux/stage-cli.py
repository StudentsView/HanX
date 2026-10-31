#!/usr/bin/env python3
"""Stage release CLI and its non-glibc runtime libraries on native Linux."""
import pathlib, re, shutil, subprocess, sys, urllib.request
binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/hanx').resolve()
out = pathlib.Path('build/platform/cli')
if out.exists():
    shutil.rmtree(out)
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
            # Distribution libraries retain their package-provided notices.
            query = subprocess.run(['dpkg-query', '-S', str(source.resolve())], text=True, capture_output=True)
            if query.returncode:
                query = subprocess.run(['dpkg-query', '-S', str(source)], text=True, capture_output=True)
            if query.returncode == 0:
                package = query.stdout.split(': ', 1)[0].split(':', 1)[0]
                copyright_file = pathlib.Path('/usr/share/doc') / package / 'copyright'
                if not copyright_file.is_file():
                    raise SystemExit('Runtime copyright missing: ' + package)
                license_dir = out / 'third-party-licenses'
                license_dir.mkdir(exist_ok=True)
                shutil.copy2(copyright_file, license_dir / (package + '-copyright.txt'))
(out / 'hanx').write_text('''#!/bin/sh
cli_path=$(readlink -f -- "$0") || exit 1
cli_dir=$(CDPATH= cd -- "$(dirname -- "$cli_path")" && pwd)
export LD_LIBRARY_PATH="$cli_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$cli_dir/hanx-engine" "$@"
''')
(out / 'hanx').chmod(0o755)
for file in ['LICENSE','NOTICE']:
    shutil.copy2(file, out / file)
licenses = out / 'third-party-licenses'
licenses.mkdir(exist_ok=True)
shutil.copy2('Sources/CMiniz/LICENSE', licenses / 'miniz.txt')

# Swift's release archives do not consistently contain the source notices.
# Include the matching upstream release's license texts in every distribution.
for repository, filename in [('swift','LICENSE.txt'), ('swift-foundation','LICENSE.md'),
                             ('swift-foundation','NOTICE.txt'), ('swift-foundation-icu','LICENSE.md'),
                             ('swift-corelibs-foundation','LICENSE'), ('swift-corelibs-libdispatch','LICENSE')]:
    url = f'https://raw.githubusercontent.com/swiftlang/{repository}/swift-6.2.1-RELEASE/{filename}'
    with urllib.request.urlopen(url, timeout=30) as response:
        (licenses / (repository + '-' + filename.replace('.md','.txt'))).write_bytes(response.read())

# Debian copyright notices refer to these standard license texts by path.
common = pathlib.Path('/usr/share/common-licenses')
if common.is_dir():
    shutil.copytree(common, licenses / 'debian-common-licenses', dirs_exist_ok=True)
