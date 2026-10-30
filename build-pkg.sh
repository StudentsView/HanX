#!/bin/zsh
# Create a signed app+CLI installer. The postinstall preserves foreign commands.
set -euo pipefail
cd "${0:A:h}"
APP_PATH="${HANX_APP_PATH:-$PWD/build/HanX.app}"
[[ -d "$APP_PATH" ]] || { print -u2 'Build HanX.app first with ./build-app.sh'; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
PKG_OUTPUT="${1:-$PWD/build/HanX-$VERSION.pkg}"
mkdir -p "${PKG_OUTPUT:h}" build
TASK_DIR=$(mktemp -d "$PWD/build/pkg-XXXXXX")
trap 'rm -rf "$TASK_DIR"' EXIT
PAYLOAD="$TASK_DIR/payload"
mkdir -p "$PAYLOAD/Applications"
ditto "$APP_PATH" "$PAYLOAD/Applications/HanX.app"
if [[ -n "${HANX_APP_SIGN_IDENTITY:-}" ]]; then
  codesign --force --identifier com.hanx.cli --options runtime --timestamp --sign "$HANX_APP_SIGN_IDENTITY" "$PAYLOAD/Applications/HanX.app/Contents/Resources/CLI/hanx"
  codesign --force --options runtime --timestamp --sign "$HANX_APP_SIGN_IDENTITY" "$PAYLOAD/Applications/HanX.app"
fi
codesign --verify --deep --strict "$PAYLOAD/Applications/HanX.app"
pkgbuild --analyze --root "$PAYLOAD" "$TASK_DIR/components.plist"
python3 - "$TASK_DIR/components.plist" "$TASK_DIR/Distribution.xml" "$VERSION" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]); components=plistlib.loads(p.read_bytes())
assert len(components)==1 and components[0]['RootRelativeBundlePath']=='Applications/HanX.app'
for c in components:
 c.update(BundleIsRelocatable=False,BundleIsVersionChecked=True,BundleHasStrictIdentifier=True,BundleOverwriteAction='upgrade')
p.write_bytes(plistlib.dumps(components))
Path(sys.argv[2]).write_text('''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
<title>HanX</title>
<welcome file="Welcome.html" mime-type="text/html"/>
<conclusion file="Conclusion.html" mime-type="text/html"/>
<options customize="never" require-scripts="true" hostArchitectures="arm64,x86_64"/>
<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
<allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
<choices-outline><line choice="hanx"/></choices-outline>
<choice id="hanx" visible="false" title="HanX"><pkg-ref id="com.hanword.editor.installer"/></choice>
<pkg-ref id="com.hanword.editor.installer" version="'''+sys.argv[3]+'''" onConclusion="none">HanX-component.pkg</pkg-ref>
</installer-gui-script>''')
PY
pkgbuild --root "$PAYLOAD" --component-plist "$TASK_DIR/components.plist" --identifier com.hanword.editor.installer --version "$VERSION" --install-location / --ownership recommended --scripts "$PWD/packaging/pkg" "$TASK_DIR/HanX-component.pkg"
SIGN_ARGS=()
if [[ -n "${HANX_PKG_SIGN_IDENTITY:-}" ]]; then SIGN_ARGS=(--sign "$HANX_PKG_SIGN_IDENTITY" --timestamp); fi
productbuild --distribution "$TASK_DIR/Distribution.xml" --resources "$PWD/Resources/Installer" --package-path "$TASK_DIR" "${SIGN_ARGS[@]}" "$PKG_OUTPUT"
if [[ -n "${HANX_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$PKG_OUTPUT" --keychain-profile "$HANX_NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG_OUTPUT"
fi
print "Created $PKG_OUTPUT"
