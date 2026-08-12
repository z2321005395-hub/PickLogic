# Apps Rules

- Apps compose packages and own navigation/presentation, not duplicate core algorithms.
- First paint must not wait for a full scan, OCR pass, PDF extraction, or duplicate hash run.
- Keep common visuals/localization in `packages/shared_ui`.
- Debug targets must visibly show and enforce Developer Safe Mode.
- Use synthetic fixtures until an explicit real-device/read-only validation step.
