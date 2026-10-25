# Third-party components in Upshift 1.0.1

Upshift runs the following components locally. Their respective licenses and
copyright notices remain applicable; these components are provided without warranty.

- **REAL Video Enhancer**, TNTwise and contributors: AGPL-3.0. Unmodified source
  at commit `8541c46ca14e6f84fc86c5b9d3b75373e25732e5` and its LICENSE are
  included in `Contents/SharedSupport/Engine/RVE`.
  https://github.com/TNTwise/REAL-Video-Enhancer
- **OpenProteus Compact 2×**, Sirosky: Creative Commons Attribution-NonCommercial
  4.0. The model is unmodified. This model carries a noncommercial restriction.
  https://github.com/Sirosky/Upscale-Hub/releases/tag/OpenProteus
  Full terms: `Contents/SharedSupport/Licenses/OpenProteus-LICENSE.md`.
- **Python 3.12.14**: Python Software Foundation license and included component
  notices, in the bundled Python standard library's `LICENSE.txt`.
  https://www.python.org/
- **PyTorch 2.7.0**, **torchvision 0.22.0**, **NumPy**, **OpenCV**, **PyAV**,
  **imageio-ffmpeg**, and other Python dependencies: full version list in
  `Scripts/requirements-mac.lock`. Original package license files remain in
  `Contents/SharedSupport/Engine/python/lib/python3.12/site-packages`, including
  the `*.dist-info/licenses` directories and OpenCV's `LICENSE-3RD-PARTY.txt`.
- **FFmpeg 7.1** command-line encoder: built from unmodified source without
  external codec libraries or GPL features; LGPL-2.1-or-later. Source and build
  instructions accompany the release. Full license in SharedSupport/Licenses.
- **PyAV's FFmpeg 9.0.2 libraries** and codec dependencies retain their upstream
  licensing, including GPL components. The release source companion includes
  the versioned vendor build recipes, patches, and source archive manifest.
  https://github.com/PyAV-Org/pyav-ffmpeg/tree/9.0.2-1

Upshift source and release source companions:
https://github.com/mingistech/UpShift/releases/tag/v1.0.1

Library replacement / rebuilding: use the published source and packaging scripts
to rebuild and sign your own copy. Changing bundled code invalidates the original
Developer ID signature; the source scripts do not require the original signing key.
