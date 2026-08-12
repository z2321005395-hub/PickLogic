# Platform Bridge Rules

- Bridges translate opaque locators and platform capabilities; they do not redefine shared models.
- Methods are minimal, cancellable where possible, and privacy-preserving in logs.
- Debug safe-mode gates live below UI calls.
- Android obeys scoped storage; Windows system inspection is read-only.
- Platform tests use generated roots/content and never mutate user data.
