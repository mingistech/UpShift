# Upshift

Upshift is a native macOS app that uses AI models to upscale videos to 2× resolution.
Built with SwiftUI, it offers Apple silicon acceleration, HEVC MP4 output, and
preserved frame rates and audio through a simple interface. Processing stays on your Mac.

## Download

Download **UpShift-1.0-macOS-arm64.zip** from the
[1.0 release](https://github.com/mingistech/UpShift/releases/tag/v1.0), unzip it,
and move **UpShift.app** to Applications. The release includes its processing
engine and models; Python, Homebrew, and separate model downloads are not needed.

Requires an **Apple silicon Mac**. The SwiftUI frontend targets macOS 14 or later;
the bundled runtime is validated on the development Mac, not every supported OS version.

## Use

Drop a video into the window, or choose **Choose Video…**, then **Upscale & Save…**.
Choose a destination and wait for the completed export. The app displays the saved
path and offers **Show in Finder**. It remembers the last completed export.

- OpenProteus Compact 2× AI upscaling on the Apple GPU.
- Original compact HEVC VideoToolbox preset: quality 65, 8-bit SDR MP4.
- Original constant frame rate and compatible audio tracks preserved.
- Progress, cancellation, and verification before replacing an existing output.
- Optional experimental compression cleanup, **off by default**. It can make
  skin and texture look artificial; leave it off when natural detail matters.

Version 1.0 supports SDR, constant-frame-rate video with one video track. HDR,
variable frame rates, and rotation metadata are rejected with an explanation.
Subtitles are omitted. Audio must be AAC, MP3, ALAC, AC-3, or E-AC-3 for MP4 copying.
Upscaling cannot guarantee recovery of detail absent from the source.

**Model license:** the bundled OpenProteus model is CC BY-NC 4.0 and carries a
noncommercial restriction. See [third-party notices](UpShift/Resources/THIRD_PARTY_NOTICES.md)
for attribution, licenses, and source references.

## Build from source

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then run:

```sh
./Scripts/setup-engine.sh
```

Open `UpShift.xcodeproj`, choose the **UpShift** scheme and **My Mac**, and Run.
Development builds use the checkout's `.runtime` folder. Packaged release builds
prefer the engine inside the app. You can select an external engine under
**Processing engine & details**.

The backend is pinned to RVE commit `8541c46ca14e6f84fc86c5b9d3b75373e25732e5`;
Python dependencies are pinned in `Scripts/requirements-mac.lock`, and model files
are verified by SHA-256. The backend runs as a separate local process.

## Verification and release packaging

```sh
xcodebuild -project UpShift.xcodeproj -scheme UpShift -configuration Debug \
  -derivedDataPath work/DerivedData CODE_SIGNING_ALLOWED=NO build
.runtime/venv/bin/python Tests/test_pipeline.py
```

Integration checks exercise actual Apple GPU upscaling, preserved audio and frame
rates, cleanup, cancellation, safe output replacement, and Finder visibility.
See [RELEASING.md](RELEASING.md) for standalone packaging and notarization.
