# ADR 0003: PDF engine evaluation gate

Status: License/capability screen complete; size experiment pending

## Context

Pro v0.1 needs local rendering, page thumbnails, search, selection, and copy. PDF engines can materially affect licenses and installer size.

## Candidate

The evaluated version is `pdfrx 2.4.7`. Its official package documentation lists Windows support, local PDFium native-asset packaging, page viewing, text selection, and search. `pdfrx` and `pdfrx_engine` use MIT; PDFium uses BSD-3 and brings third-party notices.

A workspace dry run would add 33 resolved dependencies. Because Desktop Standard and Pro share one Flutter application manifest, PDFium may also enter the Standard artifact even when only the Pro entrypoint imports its widgets.

Official sources:

- https://pub.dev/packages/pdfrx
- https://github.com/espresso3389/pdfrx
- https://github.com/PDFium/PDFium

## Alternatives

- OS preview: light but inconsistent and insufficient for cross-platform text/thumbnail behavior.
- Commercial SDKs: potentially polished but incompatible with an unconfirmed open-source/commercial policy.
- Full document-conversion suites: too large and outside v0.1.

No PDF engine is approved until CI records Standard and Pro size deltas, bundled notices, offline packaging behavior, and a synthetic PDF interaction test. If Standard exceeds 80 MB or includes disproportionate unused assets, keep the explicit skeleton and evaluate an optional Pro-only component boundary.
