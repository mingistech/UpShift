# Releasing Upshift

The app's version is 1.0.1 (build 2), bundle identifier `com.mingistech.UpShift`.
The release architecture is arm64. A release must bundle the engine; signing
only the development app leaves it dependent on the checkout's `.runtime`.

## Prepare

1. Run `Scripts/setup-engine.sh` and the pipeline tests.
2. Download `https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz` and verify SHA-256
   `40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6`.
3. Extract and build FFmpeg using:

   ```sh
   ./configure --disable-doc --disable-debug --disable-ffplay --disable-autodetect \
     --enable-videotoolbox --enable-audiotoolbox \
     --extra-cflags=-mmacosx-version-min=14.0 \
     --extra-ldflags=-mmacosx-version-min=14.0
   make -j8
   ```

4. Build the app:

   ```sh
   xcodebuild -project UpShift.xcodeproj -scheme UpShift -configuration Release \
     -derivedDataPath work/ReleaseDerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
   ```

5. Copy the app to a new staging directory. Run
   `Scripts/package-runtime.py /absolute/path/UpShift.app --ffmpeg /absolute/path/ffmpeg`.
   Use `.runtime/venv/bin/python` to run this script. It copies the Python runtime,
   locked packages, RVE source, and models, removes development interpreter links,
   and replaces imageio's static encoder with the source-built FFmpeg.
6. Include OpenProteus's `LICENSE.md` from Sirosky/Upscale-Hub as
   `Contents/SharedSupport/Licenses/OpenProteus-LICENSE.md`, and FFmpeg's
   `COPYING.LGPLv2.1` as `Contents/SharedSupport/Licenses/FFmpeg-LGPL-2.1.txt`.
   Keep all installed package license files and the bundled third-party notices.

## Verify, sign, notarize

Run the tests with `UPSHIFT_TEST_RUNTIME` set to the staged app's
`Contents/SharedSupport/Engine` and `UPSHIFT_TEST_BRIDGE` set to its
`Contents/Resources/upshift_bridge.py`. Set `PYTHONDONTWRITEBYTECODE=1` and
`PYTHONNOUSERSITE=1`. Run the test runner with the development Python, so its
synthetic source generator can use the development FFmpeg's libx264.

Run `Scripts/sign-release.py /path/UpShift.app --identity 'Developer ID Application: …'`
with the development Python. It signs each Mach-O and seals the outer app with
hardened runtime and timestamps. Do not use an ad-hoc or Apple Development
signature for the release. Verify the signed packaged engine still renders.

Create a submission zip with `ditto -c -k --sequesterRsrc --keepParent`, submit
using `xcrun notarytool submit ... --keychain-profile LabelBabyJrNotarization`, and
wait for **Accepted**. The profile is a keychain reference; never store credentials
in the repository. Staple using `xcrun stapler staple /path/UpShift.app`, validate
with `stapler validate` and `spctl --assess --type execute`, then recreate the zip
from the stapled app. Verify the final extracted archive before uploading it.

## Publish

Publish tag `v1.0.1` against the tested source commit. Attach:

- `UpShift-1.0.1-macOS-arm64.zip` (stapled app)
- the source companion containing the pinned RVE source, FFmpeg sources, vendor
  build recipes/patches and codec sources
- `SHA256SUMS.txt`

Document Apple silicon requirements, the original quality-65 preset, experimental
cleanup, input limitations, and the OpenProteus noncommercial model restriction.
No sample footage, runtime caches, keychain data, or user-specific Xcode settings
belong in a release or source commit.
