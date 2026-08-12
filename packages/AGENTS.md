# Packages Rules

- Prefer pure Dart. Only `shared_ui` may depend on Flutter UI.
- Depend inward toward `core_models`; avoid package cycles and app imports.
- Public APIs need focused tests. Keep models small and immutable.
- No platform path assumptions, raw UI file mutation, network default, telemetry, or private-data logging.
- Shared contract changes follow `docs/DATA_MODEL.md` and an ADR before implementation.
