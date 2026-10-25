# App Store listing draft

Not submitted. Review this after licensing and final sandbox validation.

**Name:** Upshift

**Subtitle:** AI video upscaling on your Mac

**Promotional text:** Give your videos more room to shine. Upscale to 2× resolution
with local AI processing, Apple silicon acceleration, and a simple Mac interface.

**Description:**

Upshift uses AI to upscale your videos to twice their original resolution, directly
on your Mac. Choose a video, pick where to save it, and let Apple silicon do the work.

- Local AI video upscaling with no account or footage upload.
- HEVC MP4 output using Apple's hardware video encoder.
- Original constant frame rate and compatible audio preserved.
- Drag-and-drop input, progress, cancellation, and Show in Finder.

Requires an Apple silicon Mac. This edition supports SDR video with a constant
frame rate. HDR, variable frame rates, and rotation metadata are not supported.
Upscaling can enhance a video, but cannot guarantee recovery of missing detail.

**Primary category:** Video

**Keywords:** video,upscale,enhance,resolution,AI,HEVC,MP4,local,Apple silicon

**Support URL candidate:** https://github.com/mingistech/UpShift/issues

**Privacy policy:** draft in `PRIVACY.md`; publish at a stable public URL before submission.

**Privacy labels draft:** Data Not Collected. Validate the final dependency audit;
there are no analytics, ads, accounts, or networking entitlements in this prototype.

**Review notes draft:**

Upshift is an offline video upscaler. No login is required. On an Apple silicon Mac,
choose an SDR constant-frame-rate MP4 with AAC audio, then choose Upscale & Save.
The app accesses only user-selected files and its private sandbox container.
AI inference and HEVC encoding run locally through bundled signed helpers.

**Still needed:** price, territories, seller/copyright details, support contact,
privacy URL, age-rating/export-compliance answers, model distribution rights,
license compatibility resolution, final screenshots, and distribution-signed build.
