"""Upload verified native CI artifacts to an existing draft release."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

if os.environ.get('GITHUB_ACTIONS') != 'true':
    raise SystemExit('Run release staging in its GitHub workflow.')
version = json.loads(Path('packaging/npm/package.json').read_text())['version']
tag = 'v' + version
repo = os.environ['GITHUB_REPOSITORY']

def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)

matches = [r for r in json.loads(gh('api', f'repos/{repo}/releases?per_page=100')) if r['tag_name'] == tag]
assert len(matches) == 1, 'Expected one existing draft release.'
release = matches[0]
assert release['draft'], 'Release staging must never replace a published release.'
run = json.loads(gh('api', f'repos/{repo}/actions/runs/{sys.argv[1]}'))
assert run['conclusion'] == 'success', 'Native release gates did not all pass.'
assert run['head_sha'] == sys.argv[2], 'Unexpected native build commit.'
assert run['path'] == '.github/workflows/platforms.yml', 'Unexpected build workflow.'

names = [f'HanX-CLI-{version}-win32-x64.zip', f'HanX-{version}-win32-x64-Setup.exe',
         f'HanX-CLI-{version}-linux-x64.tar.gz', f'HanX-{version}-linux-x64.AppImage',
         f'HanX-{version}-linux-x64.deb']
local = {}
for name in names:
    matches = list(Path('build/candidates').rglob(name))
    assert len(matches) == 1, f'Expected one verified artifact: {name}'
    local[name] = hashlib.file_digest(matches[0].open('rb'), 'sha256').hexdigest()
    gh('release', 'upload', tag, str(matches[0]), '--clobber', '--repo', repo)

release = json.loads(gh('api', f'repos/{repo}/releases/{release["id"]}'))
digests = {}
for asset in release['assets']:
    digest = asset.get('digest') or ''
    assert re.fullmatch(r'sha256:[0-9a-f]{64}', digest), f'Missing server checksum: {asset["name"]}'
    digests[asset['name']] = digest.removeprefix('sha256:')
for name, digest in local.items():
    assert digests[name] == digest, f'Uploaded checksum mismatch: {name}'

assets = []
for platform, arches in [('darwin', ['arm64', 'x64']), ('win32', ['x64']), ('linux', ['x64'])]:
    for arch in arches:
        for component in ['cli', 'gui']:
            if platform == 'darwin':
                name = f'HanX-CLI-{version}-macOS.zip' if component == 'cli' else f'HanX-{version}-macOS.zip'
            elif component == 'cli':
                name = f'HanX-CLI-{version}-{platform}-{arch}.' + ('zip' if platform == 'win32' else 'tar.gz')
            else:
                name = f'HanX-{version}-win32-x64-Setup.exe' if platform == 'win32' else f'HanX-{version}-linux-x64.AppImage'
            assert name in digests, f'Release asset is missing: {name}'
            assets.append(dict(component=component, platform=platform, arch=arch, name=name, sha256=digests[name]))
for required in [f'HanX-Setup-{version}.tar.gz', f'juyoungsuh-hanx-{version}.tgz']:
    assert required in digests, f'Release asset is missing: {required}'

output = Path('build/release-metadata'); output.mkdir(parents=True, exist_ok=True)
manifest = output / 'hanx-install-manifest.json'
manifest.write_text(json.dumps(dict(version=version, assets=assets), indent=2) + '\n')
excluded = {'SHA256SUMS', 'SHA256SUMS.txt', manifest.name}
sums = {n: d for n, d in digests.items() if n not in excluded}
sums[manifest.name] = hashlib.sha256(manifest.read_bytes()).hexdigest()
for filename in ['SHA256SUMS', 'SHA256SUMS.txt']:
    (output / filename).write_text(''.join(f'{d}  {n}\n' for n, d in sorted(sums.items())))
(output / 'native-verification.json').write_text(json.dumps(dict(version=version, run=run['html_url'], commit=run['head_sha'], checksums=local), indent=2) + '\n')
for name in [manifest.name, 'SHA256SUMS', 'SHA256SUMS.txt']:
    gh('release', 'upload', tag, str(output / name), '--clobber', '--repo', repo)
print('Verified native artifacts and installation manifest staged in the draft release.')
