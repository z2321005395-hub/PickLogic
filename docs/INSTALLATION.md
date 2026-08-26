# Alpha Installation

These packages are public alpha user-test builds. They are not production-signed installers.

## Windows Standard / Pro

1. Download the matching ZIP and `SHA256SUMS.txt` from the GitHub prerelease.
2. Verify SHA-256, then extract the complete ZIP to a new folder.
3. Start `picklogic_desktop.exe`; keep the adjacent `data` and DLL files together.
4. Standard and Pro are separate builds of one desktop codebase. Their ZIPs may be kept in separate folders.

The current Windows candidate is portable, unsigned, and does not modify the registry, services, startup items, or scheduled tasks. SmartScreen may warn because no signing certificate has been configured. Do not bypass an organizational security policy.

## Android Mobile

- `*-arm64-profile.apk` is installable for the arm64 reference-device trial and is explicitly a test-signed Profile validation build.
- `*-release-unsigned-arm64.apk` exists only for release-size measurement and cannot be installed until the maintainer configures final signing.
- Android asks for media/SAF access only after the user selects the corresponding action. Declining permission leaves the shell usable.

Grant media or folder access only when you want PickLogic to index that accessible content. The alpha remains read-only and does not access other apps' private directories.

## Developer Safe Mode

Debug builds display `Developer Safe Mode: ON`. Screenshot delete gestures only add items to an internal review queue. Real move, rename, delete, system, registry, service, task, and startup changes are unavailable.
