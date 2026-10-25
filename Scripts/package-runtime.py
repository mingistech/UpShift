"""Assemble a relocatable engine inside an unsigned release app; sign afterwards."""
import argparse
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--ffmpeg', type=Path, required=True)
p.add_argument('--app-store', action='store_true', help='Omit experimental cleanup and unused compiler tools')
args = p.parse_args()
if not args.ffmpeg.is_file():
    raise SystemExit(f'FFmpeg binary is missing: {args.ffmpeg}')
source = ROOT / '.runtime'
target = args.app / 'Contents/SharedSupport/Engine'
if target.exists():
    raise SystemExit(f'Refusing to replace existing runtime: {target}')
target.mkdir(parents=True)
ignore = shutil.ignore_patterns('.git', '__pycache__', '*.pyc', '.DS_Store', '*.a')
python = (source / 'python/cpython-3.12-macos-aarch64-none').resolve()
shutil.copytree(python / 'lib', target / 'python/lib', symlinks=True, ignore=ignore)
(target / 'python/bin').mkdir(parents=True)
shutil.copy2(python / 'bin/python3.12', target / 'python/bin/python3.12')
shutil.copytree(source / 'venv/lib/python3.12/site-packages', target / 'python/lib/python3.12/site-packages', dirs_exist_ok=True, symlinks=True, ignore=ignore)
# No venv configuration or absolute interpreter links survive relocation.
(target / 'venv/bin').mkdir(parents=True)
(target / 'venv/bin/python').symlink_to('../../python/bin/python3.12')
shutil.copytree(source / 'RVE', target / 'RVE', symlinks=True, ignore=ignore)
config = json.loads((source / 'engine.json').read_text())
if args.app_store:
    config.pop('restoration_model', None)
    config.pop('restoration_sha256', None)
    for tool in ('protoc', 'protoc-3.13.0.0'):
        (target / 'python/lib/python3.12/site-packages/torch/bin' / tool).unlink(missing_ok=True)
for key in ('model', 'restoration_model'):
    if key not in config:
        continue
    dest = target / config[key]
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / config[key], dest)
(target / 'engine.json').write_text(json.dumps(config, indent=2) + '\n')
# Replace the third-party static GPL encoder with our source-built LGPL FFmpeg.
binaries = target / 'python/lib/python3.12/site-packages/imageio_ffmpeg/binaries'
for file in binaries.glob('ffmpeg-*'):
    file.unlink()
shutil.copy2(args.ffmpeg, binaries / 'ffmpeg-macos-aarch64-v7.1')
for link in target.rglob('*'):
    if link.is_symlink():
        if not link.exists() or not link.resolve().is_relative_to(target.resolve()):
            raise SystemExit(f'Nonportable link: {link}')
print(target)
