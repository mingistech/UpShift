"""Sign embedded Mach-O code from the inside out, then seal the app."""
import argparse
from pathlib import Path
import subprocess
import struct

p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--identity', required=True)
p.add_argument('--app-store', action='store_true', help='Sign helpers for inherited sandboxing and apply app entitlements')
a = p.parse_args()
magics = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
entitlements = Path(__file__).resolve().parents[1] / 'Configuration/AppStore'

def is_executable(path):
    with path.open('rb') as f:
        header = f.read(16)
        if header[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            f.seek(16)
            offset = struct.unpack('>I', f.read(4))[0] if header[:4] == b'\xca\xfe\xba\xbe' else struct.unpack('>Q', f.read(8))[0]
            f.seek(offset)
            header = f.read(16)
        return header[:4] == b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I', header, 12)[0] == 2

files = []
for path in a.app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as f:
            if f.read(4) in magics:
                files.append(path)
for i, path in enumerate(sorted(files), 1):
    command = ['codesign', '--force', '--sign', a.identity, '--timestamp', '--options', 'runtime']
    if a.app_store and is_executable(path) and path != a.app / 'Contents/MacOS/UpShift':
        command += ['--entitlements', str(entitlements / 'Helper.entitlements')]
    command.append(str(path))
    subprocess.run(command, check=True, capture_output=True)
    if i % 50 == 0:
        print(f'Signed {i}/{len(files)} binaries', flush=True)
command = ['codesign', '--force', '--sign', a.identity, '--timestamp', '--options', 'runtime']
if a.app_store:
    command += ['--entitlements', str(entitlements / 'UpShift.entitlements')]
command.append(str(a.app))
subprocess.run(command, check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(a.app)], check=True)
print(f'Signed app and {len(files)} nested binaries')
