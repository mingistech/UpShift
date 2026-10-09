#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo 'Upshift currently requires an Apple silicon Mac.' >&2
    exit 1
fi
UV_BIN="$(command -v uv || true)"
if [[ -z "$UV_BIN" && -x /opt/homebrew/bin/uv ]]; then UV_BIN=/opt/homebrew/bin/uv; fi
if [[ -z "$UV_BIN" ]]; then
    echo 'Install uv from https://docs.astral.sh/uv/getting-started/installation/ and run this script again.' >&2
    exit 1
fi
mkdir -p .runtime/models
export UV_CACHE_DIR="$PROJECT_DIR/.runtime/cache"
export UV_PYTHON_INSTALL_DIR="$PROJECT_DIR/.runtime/python"
RVE_COMMIT=8541c46ca14e6f84fc86c5b9d3b75373e25732e5
if [[ ! -d .runtime/RVE ]]; then
    git clone --no-checkout https://github.com/TNTwise/REAL-Video-Enhancer.git .runtime/RVE
    git -C .runtime/RVE checkout --detach "$RVE_COMMIT"
fi
if [[ "$(git -C .runtime/RVE rev-parse HEAD)" != "$RVE_COMMIT" ]]; then
    echo 'The installed RVE revision differs from the tested revision. Move .runtime/RVE aside and rerun setup.' >&2
    exit 1
fi
if [[ -n "$(git -C .runtime/RVE status --porcelain --untracked-files=no)" ]]; then
    echo 'The RVE source has local edits. Move .runtime/RVE aside and rerun setup.' >&2
    exit 1
fi
if [[ ! -x .runtime/venv/bin/python ]]; then
    "$UV_BIN" venv --python 3.12.14 .runtime/venv
fi
"$UV_BIN" pip sync --python .runtime/venv/bin/python Scripts/requirements-mac.lock
MODEL_FILE=.runtime/models/2x_OpenProteus_Compact_i2_70K.pth
if [[ ! -f "$MODEL_FILE" ]]; then
    curl -fL --retry 2 'https://github.com/TNTwise/real-video-enhancer-models/releases/download/models/2x_OpenProteus_Compact_i2_70K.pth' -o "$MODEL_FILE.download"
    mv "$MODEL_FILE.download" "$MODEL_FILE"
fi
RESTORATION_FILE=.runtime/models/1xDeH264_RTMoSR.pth
if [[ ! -f "$RESTORATION_FILE" ]]; then
    curl -fL --retry 2 'https://github.com/TNTwise/real-video-enhancer-models/releases/download/models/1xDeH264_RTMoSR.pth' -o "$RESTORATION_FILE.download"
    mv "$RESTORATION_FILE.download" "$RESTORATION_FILE"
fi
.runtime/venv/bin/python - <<'PY'
from pathlib import Path
import hashlib
import json
import subprocess
import imageio_ffmpeg
import torch
model = Path('.runtime/models/2x_OpenProteus_Compact_i2_70K.pth')
checksum = 'a943566242a830ace576b768921a63ddde2baf826b90712e869d937603008708'
if hashlib.sha256(model.read_bytes()).hexdigest() != checksum:
    raise SystemExit('Model integrity check failed. Remove the model file and rerun setup.')
restoration = Path('.runtime/models/1xDeH264_RTMoSR.pth')
restoration_checksum = 'a53b2acf99ba2eacf2873892724113d1782fc8711ca9bc460dfccb59ccd990b3'
if hashlib.sha256(restoration.read_bytes()).hexdigest() != restoration_checksum:
    raise SystemExit('Cleanup model integrity check failed. Remove it and rerun setup.')
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
encoders = subprocess.check_output([ffmpeg, '-hide_banner', '-encoders'], text=True)
if 'hevc_videotoolbox' not in encoders:
    raise SystemExit('The installed FFmpeg build is missing HEVC VideoToolbox.')
if not torch.backends.mps.is_available():
    raise SystemExit('Apple GPU processing is unavailable in this environment.')
config = {'backend': 'RVE/backend/rve-backend.py', 'model': str(model.relative_to('.runtime')),
          'model_sha256': checksum, 'restoration_model': str(restoration.relative_to('.runtime')),
          'restoration_sha256': restoration_checksum, 'rve_commit': '8541c46ca14e6f84fc86c5b9d3b75373e25732e5'}
Path('.runtime/engine.json').write_text(json.dumps(config, indent=2) + '\n')
print('Upshift engine ready. Open UpShift.xcodeproj and run the UpShift scheme.')
PY
