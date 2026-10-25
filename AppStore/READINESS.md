# Mac App Store preparation

Branch: `codex/mac-app-store` (started 2026-10-24 from the 1.0.1 source).
This branch is a development prototype. It is not a submission-ready release.

## Implemented foundation

- App Sandbox enabled, with user-selected read/write access and app-scoped bookmarks.
- Bundled engine required; no external engine selection or runtime installation.
- User-selected input copied into private temporary storage before any helper runs.
- Engine output verified inside the container, then saved with NSFileCoordinator
  and a same-volume Foundation replacement directory. The original is protected.
- Scoped access retained through preview/export; last output restored through a
  security-scoped bookmark rather than an unprivileged saved path.
- Python, FFmpeg and other executable helpers signed with inherited sandboxing.
- No networking, app groups, temporary sandbox exceptions, or JIT entitlements requested.
- Experimental cleanup removed from this edition and its model omitted from packaging.
- Privacy manifest added for app preferences, file metadata, and elapsed-time measurement.
- Video category set; existing icon and branding retained.

## Must resolve before App Store upload

### 1. Model rights

The currently tested model is OpenProteus, SHA-256
`a943566242a830ace576b768921a63ddde2baf826b90712e869d937603008708`.
The author's repository applies **CC BY-NC 4.0**. Do not assume that making an app
free resolves App Store distribution rights. Obtain permission explicitly covering
this distribution and intended pricing/use, or choose a model with appropriate
rights and compare its output before replacing the current model.

Source: https://github.com/Sirosky/Upscale-Hub/blob/main/LICENSE.md

### 2. Engine and library licensing

RVE is AGPL-3.0; PyAV's bundled FFmpeg includes GPL codec components. The source-built
standalone encoder is LGPL, but replacing that encoder does not remove GPL libraries
inside PyAV. Complete a component-by-component compatibility review of the intended
App Store terms, distribution, and any content protection before shipping. If the
required permissions/terms cannot be satisfied, replace these components. A native
AVFoundation + Core ML path is an alternative to investigate, not yet implemented.
The optional cleanup model is excluded to reduce the initial rights surface.

Source: included RVE LICENSE, Python wheel license notices, and
https://github.com/PyAV-Org/pyav-ffmpeg/tree/9.0.2-1

### 3. Submission signing and account setup

A Developer ID sandbox prototype is useful for testing but is not a Mac App Store
submission. Configure Apple Distribution / Mac App Distribution signing, the matching
provisioning profile, and an App Store Connect record for `com.mingistech.UpShift`.
The preview uses `com.mingistech.UpShift.StorePreview` to isolate its container.
No App Store record, agreement, pricing, or external submission has been created.
`Configuration/AppStore/ExportOptions.plist.example` is a starting template for a
future distribution-signed archive, not an upload command.

### 4. Product and store metadata

- Choose free/paid and any distribution territories.
- Confirm copyright holder, seller information, support contact, and privacy URL.
- Complete the age-rating and export-compliance questionnaires from actual behavior.
- Prepare required screenshots at Apple's accepted sizes from the final store build.
- Validate on a clean Apple silicon Mac and macOS 14 as well as the current OS.
- Test Files/iCloud/external-volume imports, overwrite, cancellation, relaunch bookmarks,
  low space, crashes, and saving after a long render. Temporary copies need free space
  for input, output, and a same-volume replacement copy during export.
- Audit native SDK required-reason API use and any additional manifests; the initial
  app manifest does not substitute for a complete third-party SDK audit.
- Validate a distribution-signed archive in Xcode/Transporter, then TestFlight/App Review.

Apple references:
- https://developer.apple.com/app-store/review/guidelines/ (2.4.5, 2.5.2, 5.2)
- https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app
- https://developer.apple.com/documentation/security/app-sandbox
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration

## Local sandbox preview

Run `Scripts/prepare-app-store.sh`. This builds and signs a separate sandboxed
preview with the existing local engine. The output path is saved in
`work/app-store-preview-path.txt`. Default signing uses the existing Developer ID;
pass another identity as the first argument if needed. It does not upload anything.

Run `Scripts/check-app-store.py /path/to/UpShift.app --prototype` to inspect the
preview. Without `--prototype`, known submission blockers produce a nonzero exit.

The script requires `.runtime` and the source-built FFmpeg from `RELEASING.md`.
Do not use `notarytool` as a substitute for App Store archive validation; notarization
is the direct-distribution workflow, not App Store submission.

Filesystem checks:

```sh
swiftc -parse-as-library UpShift/SandboxFiles.swift Tests/SandboxFilesChecks.swift \
  -o work/SandboxFilesChecks
work/SandboxFilesChecks
```

Actual sandbox tests must launch the signed app, choose files through native panels,
and exercise the inherited helpers. Running Python from a terminal does not prove
that the app's sandbox works. See `VALIDATION.md` for the recorded results.
