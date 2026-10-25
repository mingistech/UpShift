# Draft licensing inquiries

These drafts have not been sent. Resolve the intended price and publisher details
before contacting anyone or accepting terms. Written permission must cover the
specific weights/code and the intended distribution; a free listing alone is not
proof of permission.

## OpenProteus author

Reference: https://github.com/Sirosky/Upscale-Hub/releases/tag/OpenProteus

Hello,

I'm preparing Upshift, a native macOS video-upscaling app, for the Mac App Store.
The current prototype uses your unmodified OpenProteus Compact 2× model
`2x_OpenProteus_Compact_i2_70K.pth` (SHA-256
`a943566242a830ace576b768921a63ddde2baf826b90712e869d937603008708`).

I see the repository's CC BY-NC 4.0 license. Is a separate license available that
explicitly permits bundling and redistributing these weights in a Mac App Store
app, including a paid listing and commercial end-user video processing? Please
also confirm any restrictions relating to Apple's distribution/content-protection
terms, and the required attribution, license notices, and availability of the weights.

All video processing runs locally; user footage is not uploaded to a service.

Thank you.

## RVE licensing clarification

Reference: https://github.com/TNTwise/REAL-Video-Enhancer

Hello,

I'm evaluating a Mac App Store edition of Upshift using the unmodified RVE backend
at commit `8541c46ca14e6f84fc86c5b9d3b75373e25732e5`, as a bundled local subprocess.

I see the AGPL-3.0 license. Is an App Store-compatible licensing option or exception
available for code you control? Which third-party or contributor-owned components
would still require separate permissions or different terms? I want to confirm the
requirements before preparing a Store submission, rather than assuming that
providing source or using a separate process resolves every distribution condition.

The prototype also contains PyAV's FFmpeg libraries with GPL codecs. I understand
that any RVE permission would not, by itself, grant permissions for those libraries
or the model weights.

Thank you.

## Technical alternatives if permissions are unavailable

- Evaluate a suitably licensed 2× model, with explicit weight redistribution and
  commercial-use terms. Compare the user's footage against the original OpenProteus
  result before changing the default; the user preferred natural detail to aggressive
  restoration and very large exports.
- Build PyAV against a verified LGPL-only FFmpeg configuration and appropriate codec
  dependencies, instead of assuming its published wheel is GPL-free.
- Evaluate a native AVFoundation / Core ML implementation if the Python/RVE licensing
  or review path cannot be resolved. This is an architectural alternative, not a
  completed conversion or a guarantee of approval.
