# ADR 0011: Reader Focus and No-key Selection Translation

Status: Accepted — 2026-08-28

## Context

The Literature workspace could keep the collection tree, library list, and page thumbnails visible while reading, leaving too little width for a PDF. Selection translation also required an endpoint, model, and API key before its otherwise automatic sidebar workflow could produce a result.

## Decision

- Make the collection pane, literature list, and PDF page thumbnails independently collapsible.
- Add one Focus reading action that hides all three and restores them together.
- Keep every restore control in the persistent workspace/reader toolbar; collapsing a pane never traps the user.
- Offer a no-key MyMemory short-text provider as a one-click engine, limited to 500 characters per call. The distribution default remains off until the user selects an engine; that choice is then remembered locally.
- Show the engine selector directly in the translation sidebar. Switching engines retries the current selection without another confirmation dialog.
- Preserve the OpenAI-compatible provider as an optional advanced engine with DPAPI-protected credentials.
- Display bounded alternative translation-memory matches as separate labeled cards.
- Add a fast aggregate choice that starts independent sources concurrently, emits exact local terminology or cache hits first, and appends slower results without delaying the first card.
- Keep a bounded in-memory result cache, deduplicate identical in-flight requests, reuse the MyMemory HTTP connection, reduce the stable-selection debounce to 90 ms, and split multibyte selections into parallel requests of at most 500 UTF-8 bytes.
- Add no package, runtime, model, copied source, or binary.

## Privacy and compatibility

Selecting text is the explicit request that sends only that selection to the named service. PDF bytes, images, paths, filenames, and library metadata stay local. Aggregate mode always uses local terminology/cache and MyMemory; it also uses the optional AI provider only when that provider was already configured by the user. Page and document translation remain explicit actions. `publicAnonymous`, optional alternatives, and `ProgressiveTranslationProvider` are additive; persisted literature and translation schemas do not change.

## Rejected options

- Do not hardcode Google or Youdao credentials; their official APIs require authenticated projects or application secrets.
- Do not scrape undocumented web endpoints because availability and redistribution terms are unstable.
- Do not embed Saladict's browser/Tauri runtime or an offline Python/model stack into the Pro base package.
- Do not present MyMemory translation-memory candidates as separate vendors. They remain honestly labeled as candidates, while genuinely independent configured sources get their own cards.
