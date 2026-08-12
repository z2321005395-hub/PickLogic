# Mobile App Rules

- Track C owns this directory and `platform/android_bridge`.
- Primary tabs are Files, Screenshots, Photos, Storage; keep auxiliary routes secondary.
- Use MediaStore and SAF; obey scoped storage and expose inaccessible areas honestly.
- Never OCR all screenshots at first launch. Thumbnails and perceptual hashes are bounded, lazy background work.
- Development delete gestures only enqueue an internal review item; they never delete media.
