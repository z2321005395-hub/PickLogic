# ADR 0001: Flutter workspace and target composition

Status: Accepted for Bootstrap

## Context

PickLogic needs Windows Standard, Windows Pro, and Android while sharing models and algorithms and keeping installers small.

## Decision

Use one native Dart workspace. Pure Dart packages hold core data and algorithms. `apps/desktop` has two entrypoints and one UI implementation; Pro composes additional feature packages. `apps/mobile` composes the same core with an Android bridge. Native bridge code is narrow and platform-specific.

## Consequences

- Shared behavior is tested once and reused.
- Platform locators stay opaque to the core.
- Pro does not fork the desktop app.
- Contract changes require compatibility review.
- Some platform capabilities need explicit bridge tests.
