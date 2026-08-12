# Tools Rules

- Tools are deterministic, non-interactive where practical, and safe by default.
- Validate resolved roots before any recursive mutation; generated cleanup is manifest-driven.
- Print summaries on success and detailed diagnostics only on failure.
- Never print environment secrets, GitHub tokens, device serials, or private paths into committed reports.
