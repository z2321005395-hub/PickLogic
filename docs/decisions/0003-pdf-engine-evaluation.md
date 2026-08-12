# ADR 0003: PDF engine evaluation gate

Status: Hosted size/license gates pass; packaged engine smoke pending

## Context

Pro v0.1 needs local rendering, page thumbnails, search, selection, and copy. PDF engines can materially affect licenses and installer size.

## Candidate

The evaluated version is `pdfrx 2.4.7`. Its official package documentation lists Windows support, local PDFium native-asset packaging, page viewing, text selection, and search. `pdfrx` and `pdfrx_engine` use MIT; PDFium uses BSD-3 and brings third-party notices.

A workspace dry run adds 33 resolved dependencies. Because Desktop Standard and Pro share one Flutter application manifest, PDFium may also enter the Standard artifact even when only the Pro entrypoint uses its widgets.

The package build hook downloads `pdfium-win-x64.tgz` from the fixed `chromium/7811` release and extracts only `pdfium.dll`; it does not verify a checksum or preserve the archive's notices. The isolated experiment therefore adds a release packaging gate that:

- requires archive SHA-256 `2e7af12674ac3716cb0e20369bb9fb269ceadfa2f0b0597097a520e6834175a0`;
- requires DLL SHA-256 `019b6ee6e54e5508002e43c5199b00f6caca26d32dd23c7bb229ff6855cd5394`;
- copies the root license and all 15 third-party license files beside the executable;
- records source URL and PDFium version `149.0.7811.0` in the package.

The 3,718,879-byte archive passed `gh attestation verify` against `bblanchon/pdfium-binaries`. The extracted DLL is 7,176,704 bytes. This is supply-chain evidence, not a legal conclusion.

Linux x64 CI tests use the matching attested archive: SHA-256 `e76e0a37aefb843d56f04657475ce612157021b1ebc53d801f2fbfcc537ccf64`; its `libpdfium.so` SHA-256 is `d106072a29b3689a5d6739948f98a97fe3ec82f5a1c309dc44e86f6c549fb44e`. PickLogic prefetches with three bounded retries, verifies these hashes, and writes the verified library to the Dart native-assets shared cache before Flutter invokes the upstream hook.

Official sources:

- https://pub.dev/packages/pdfrx
- https://github.com/espresso3389/pdfrx
- https://github.com/PDFium/PDFium
- https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7811

## Alternatives

- OS preview: light but inconsistent and insufficient for cross-platform text/thumbnail behavior.
- Commercial SDKs: potentially polished but incompatible with an unconfirmed open-source/commercial policy.
- Full document-conversion suites: too large and outside v0.1.

The experiment implements a two-page generated PDF reader with bounded image cache, page thumbnails, text selection/copy, search, highlighting, and page navigation. Unit/widget tests use an injected reader boundary because `flutter test` does not package the Windows native asset; actual PDFium behavior must be checked from the packaged executable.

No PDF engine is approved until CI records Standard and Pro size deltas, confirms bundled notices, and the packaged Pro executable passes a synthetic PDF interaction smoke test. If Standard exceeds 80 MB or includes disproportionate unused assets, withdraw the dependency and evaluate a Pro-only component boundary.

## Hosted measurement

Run `31622068263` produced:

- Standard: 39,313,910 bytes installed, 17,392,260-byte ZIP; +7,707,517 installed bytes from baseline.
- Pro: 40,165,878 bytes installed, 17,739,463-byte ZIP; +8,330,109 installed bytes from baseline.
- Both packages contain one hash-matched 7,176,704-byte DLL, the root license, all 15 third-party notices, VERSION, and PickLogic provenance.

The shared desktop manifest places PDFium in both artifacts. At 46.9% of the Standard budget and 29.5% of the Pro budget, this remains within the small-install target and provides the native base for Standard PDF preview. Deleting the declared native asset after build would create a fragile package, so this experiment retains and discloses it. Final acceptance still requires the packaged Pro engine self-check and an Android build showing no Mobile size regression.
