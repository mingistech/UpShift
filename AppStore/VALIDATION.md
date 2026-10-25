# Sandbox prototype validation

Dates: October 24–25, 2026. Host: Apple silicon, macOS 27.2, Xcode 27 SDK.

Tested app: signed standalone sandbox preview using
`com.mingistech.UpShift.StorePreview`. This separates its sandbox container from
the production bundle ID. It is Developer ID signed for local testing, not signed
or provisioned for Mac App Store submission.

## Passed

| Check | Evidence |
| --- | --- |
| Release build | arm64 frontend compiles with App Sandbox, read/write file selection, app-scoped bookmarks, and Video category. |
| Native file operations | `Tests/SandboxFilesChecks.swift` verifies input staging, new export, replacement, failure preserving the previous output, explicit rejection of saving over the original, and clearing hidden flags. |
| Real sandbox processing | Selected a synthetic 640×360 SDR MP4 through NSOpenPanel in the signed app. Produced 1280×720 HEVC, 48 frames, exactly 24/1 fps, and one unchanged AAC track. The bridge's audio-packet hashes and timing validation passed. |
| Private helper paths | Engine logs showed source and output paths inside the preview's `Library/Containers/.../Data/tmp/Upshift-*` directory. Python/RVE/FFmpeg operated on those copies, not user-selected paths. |
| Confirmed overwrite | Repeated processing, accepted the native Replace prompt, and verified the saved output again. |
| Cancellation | Started an 8-second 1280×720 test with an existing output, then cancelled. SHA-256 hashes of original and previous output were unchanged. The private job folder was gone and no engine helpers remained running. |
| Bookmark restoration | Quit and relaunched the signed app. It displayed Last completed export and the correct saved path using an app-scoped bookmark. Retested restoration with silent/non-mounting resolution. |
| Final coordinated-input revision | Ran another real export after adding NSFileCoordinator for input copies. Full dimension/codec/frame-rate/frame-count/audio verification passed. |
| Structural audit | `Scripts/check-app-store.py --prototype` passed: app sandbox, three correctly entitled executable helpers, self-contained relative links, icon, privacy manifest, and signatures. |
| Syntax/configuration | Swift build, Python compile checks, plist validation, and `git diff --check` passed. |

The three inherited executable helpers are Python, FFmpeg, and PyTorch's shared
memory manager. Unused protoc compiler binaries and the experimental cleanup model
are omitted. The app requests no network permission or temporary sandbox exception.

`Scripts/check-app-store.py` without `--prototype` intentionally returns a failure
status while the known submission blockers remain. Passing the prototype audit is
not a claim of licensing clearance or App Store approval.

## Still requires validation / decisions

- Model distribution/commercial rights and AGPL/GPL compatibility with intended
  Store terms, or approved component replacements.
- Apple Distribution signing, provisioning, archive validation and App Store Connect.
- Complete native dependency privacy/required-reason API audit.
- Clean-machine and macOS 14 testing, external volumes, iCloud/File Provider files,
  sandbox drag-and-drop grants, low space, and long footage.
- Final listing, privacy contact/URL, age/export questionnaires, pricing and screenshots.

No App Store submission or listing has been published. No licensing inquiry was sent.
