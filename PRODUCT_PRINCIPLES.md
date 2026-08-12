# Product Principles

## Small

- Do not bundle large AI models, training frameworks, Python, Node, PyTorch, CUDA, or model servers.
- OCR, advanced PDF components, local models, and online intelligence are optional and disclose their separate size.
- The product remains fully useful with all AI features disabled.
- Base install targets: Android <= 40 MB; Windows Standard <= 80 MB; Windows Pro <= 130 MB.
- Budgets are honest design targets, never achieved by hiding or misreporting files.

## Low operation cost

- Apply the `3-click rule`: common actions should usually take no more than three interactions.
- First launch never asks users to configure models, OCR, thresholds, scan rules, databases, APIs, or many folders.
- Use progressive disclosure for advanced settings.

## Refined, restrained UI

- Use shared design tokens, clear spacing, moderate radii, restrained animation, dark/light themes, and Chinese/English architecture.
- No ads, forced login, default telemetry, button walls, AI-star branding, exaggerated cleanup scores, or labels that call uncertain files trash.
- Complexity belongs inside the implementation, not on the first screen.

## Local first

- Files, OCR results, indexes, and explanations stay local by default.
- Browsing and organization do not require an account or network.
- Never upload full PDFs, photos, or documents. Network features are explicit opt-in.
- Online translation sends only text the user explicitly selects.

## Safety first

Guiding rule: **If we do not understand it, we do not delete it.**

- `SAFE`: clearly regenerable and safe to clean.
- `REVIEW`: possibly actionable, but requires review.
- `PROTECTED`: system/application critical or user-protected.
- `UNKNOWN`: insufficient evidence.
- `PROTECTED` and `UNKNOWN` never expose a direct-delete action.
- Every mutation follows `Plan -> Preview -> User confirmation -> Execute -> Undo/Trash`.
