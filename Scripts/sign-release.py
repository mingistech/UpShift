"""Sign embedded Mach-O code from the inside out, then seal the app."""
import argparse
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--identity', required=True)
a = p.parse_args()
magics = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
files = []
for path in a.app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as f:
            if f.read(4) in magics:
                files.append(path)
for i, path in enumerate(sorted(files), 1):
    subprocess.run(['codesign', '--force', '--sign', a.identity, '--timestamp', '--options', 'runtime', str(path)], check=True, capture_output=True)
    if i % 50 == 0:
        print(f'Signed {i}/{len(files)} binaries', flush=True)
subprocess.run(['codesign', '--force', '--sign', a.identity, '--timestamp', '--options', 'runtime', str(a.app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(a.app)], check=True)
print(f'Signed app and {len(files)} nested binaries')
