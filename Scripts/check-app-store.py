"""Inspect a sandbox prototype; default mode also rejects known submission blockers."""
import argparse
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--prototype', action='store_true', help='Check technical structure without treating known submission blockers as a passing release')
a = p.parse_args()
app = a.app.resolve()
failures = []
blockers = []

def require(condition, message):
    if not condition:
        failures.append(message)

def entitlements(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(path)], capture_output=True)
    try:
        return plistlib.loads(result.stdout)
    except Exception:
        return {}

def executable(path):
    with path.open('rb') as f:
        b = f.read(16)
        if b[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            f.seek(16)
            offset = struct.unpack('>I', f.read(4))[0] if b[:4] == b'\xca\xfe\xba\xbe' else struct.unpack('>Q', f.read(8))[0]
            f.seek(offset)
            b = f.read(16)
        return b[:4] == b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I', b, 12)[0] == 2

info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
main = app / 'Contents/MacOS' / info['CFBundleExecutable']
rights = entitlements(app)
require(rights.get('com.apple.security.app-sandbox') is True, 'Main app is not sandboxed.')
require(rights.get('com.apple.security.files.user-selected.read-write') is True, 'User-selected read/write access is missing.')
require(rights.get('com.apple.security.files.bookmarks.app-scope') is True, 'App-scoped bookmark entitlement is missing.')
require(not any(k.startswith('com.apple.security.temporary-exception') for k in rights), 'Temporary sandbox exceptions must not be used.')
require(not rights.get('com.apple.security.network.client'), 'Unexpected networking entitlement: review the offline privacy claim.')
require(info.get('LSApplicationCategoryType') == 'public.app-category.video', 'Video App Store category is missing.')
require(bool(info.get('CFBundleIconName')), 'App icon is not configured.')
privacy = app / 'Contents/Resources/PrivacyInfo.xcprivacy'
require(privacy.exists(), 'Privacy manifest is missing.')
if privacy.exists():
    values = plistlib.loads(privacy.read_bytes())
    require(values.get('NSPrivacyTracking') is False, 'Unexpected tracking declaration.')
engine = app / 'Contents/SharedSupport/Engine'
require((engine / 'venv/bin/python').exists(), 'Bundled Python is missing.')
require((engine / 'engine.json').exists(), 'Bundled engine configuration is missing.')
helper_count = 0
for path in app.rglob('*'):
    if path.is_symlink():
        require(path.exists() and path.resolve().is_relative_to(app), f'Nonportable link: {path.relative_to(app)}')
    elif path.is_file() and path != main and executable(path):
        helper_count += 1
        e = entitlements(path)
        require(e == {'com.apple.security.app-sandbox': True, 'com.apple.security.inherit': True},
                f'Helper does not have exactly the inherited sandbox entitlements: {path.relative_to(app)}')
require(helper_count > 0, 'No packaged executable helpers found.')
verified = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
require(verified.returncode == 0, 'Signature verification failed: ' + verified.stderr.strip())
if (engine / 'engine.json').exists():
    config = json.loads((engine / 'engine.json').read_text())
    require('restoration_model' not in config, 'Experimental cleanup model is still packaged.')
    if config.get('model_sha256') == 'a943566242a830ace576b768921a63ddde2baf826b90712e869d937603008708':
        blockers.append('OpenProteus CC BY-NC model: App Store distribution/commercial rights remain unresolved.')
blockers.append('RVE AGPL and bundled PyAV GPL codecs: resolve Store-compatible licensing or replace these components.')
signature = subprocess.run(['codesign', '-dvv', str(app)], capture_output=True, text=True).stderr
if not any(name in signature for name in ('Authority=Apple Distribution:', 'Authority=3rd Party Mac Developer Application:')):
    blockers.append('Not signed with a Mac App Store distribution identity.')
if not (app / 'Contents/embedded.provisionprofile').exists():
    blockers.append('Mac App Store provisioning profile is missing.')
if info.get('CFBundleIdentifier') != 'com.mingistech.UpShift':
    blockers.append('Preview bundle identifier must be replaced with the registered production app ID.')
if rights.get('com.apple.security.get-task-allow'):
    blockers.append('Debugging entitlement must be absent from the submitted app.')
for failure in failures:
    print('FAIL:', failure)
if not failures:
    print(f'PASS: sandbox configuration, {helper_count} inherited helpers, portable runtime, icon, privacy manifest, and signatures.')
for blocker in blockers:
    print('SUBMISSION BLOCKER:', blocker)
print('This structural check does not replace Xcode/App Store Connect validation or a licensing/SDK audit.')
sys.exit(1 if failures else (2 if blockers and not a.prototype else 0))
