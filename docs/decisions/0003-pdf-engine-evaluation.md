# ADR 0003: PDF engine evaluation gate

Status: Proposed

## Context

Pro v0.1 needs local rendering, page thumbnails, search, selection, and copy. PDF engines can materially affect licenses and installer size.

## Candidate

Evaluate `pdfrx`/PDFium because it supports Flutter Windows and Android with local rendering and text features. Before acceptance verify current package and bundled third-party licenses, exact native binaries, offline packaging, release-size delta, text-selection quality, and maintenance activity.

## Alternatives

- OS preview: light but inconsistent and insufficient for cross-platform text/thumbnail behavior.
- Commercial SDKs: potentially polished but incompatible with an unconfirmed open-source/commercial policy.
- Full document-conversion suites: too large and outside v0.1.

No PDF engine is approved until a measured artifact audit completes.
