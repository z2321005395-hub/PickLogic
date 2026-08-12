# Device Baselines

Only aggregate, non-private validation data belongs here. Never record device serials, personal filenames, document titles, or screenshots.

## Windows reference machine

- OS family: Windows 11 x64.
- Exact build observed during Bootstrap: 10.0.26200.0.
- Flutter Windows compiler: pending Visual Studio Build Tools installation/verification.
- Development behavior: synthetic directories only for mutation tests; real directories remain read-only.

## Android reference phone

Verified with ADB on 2026-08-12:

- Manufacturer/brand: nubia.
- Model: NX736J.
- Android: 15.
- API level: 35.
- ABI: arm64-v8a only.
- Build type: user.
- Security patch reported by device: 2025-11-01.
- Intended scale checks: about 17,895 images, 6,133 screenshots, and 5,618 camera images; these are user-provided planning figures until measured read-only.

No image metadata index or performance benchmark has been run yet; the ABI query read device properties only.

## Local Android development toolchain

- Reused location: `%USERPROFILE%\Desktop\ttdt\toolchains` (local-only path; never emitted to public logs).
- Temurin JDK 17.0.19, Gradle 9.4.1, Android SDK Platform/Build Tools 36, Platform Tools 37.0.0, Emulator 36.6.11.
- Existing AVDs: one API 23 x86 legacy image and one API 36 x86_64 modern image.
- PickLogic tooling must consume this environment without modifying TTDT source or artifacts.
- On 2026-08-13, Flutter's Android Gradle build automatically installed CMake 3.22.1 inside the TTDT SDK (2,992 files, 39,366,979 bytes / 37.5 MiB). This was not a system-wide install and was not removed.

## Android emulator validation

- TTDT `TTDT_Modern_64`: Android 16 / API 36 / x86_64; launched headlessly on an emulator-only ADB serial.
- A temporary x86_64 Debug APK (not a release asset) installed and cold-launched; Developer Safe Mode and all four primary destinations were visible.
- Files, Screenshots, and Photos displayed their no-permission states without requesting access or reading media.
- Local Flutter plugin generation was blocked because Windows Developer Mode is off. VM heap evidence identified `MissingPluginException`; this remains a local development-tooling limit.
- The app now bounds bootstrap platform reads and shows a safe retryable error instead of an infinite Storage spinner when platform initialization fails.
- Opt-in CI run `31639131268` built a 64,724,478-byte, v2-signed, x86_64-only Debug APK. Its SHA-256 was `49f93853...ffc7`, and static DEX inspection found the bridge class plus generated registration call.
- The CI APK cold-launched in 3.709 seconds on the TTDT API 36 emulator. Safe Mode, all four destinations, the no-permission state, and Storage Insight rendered through the real bridge; media grants and fatal-log matches were both zero.
- The old PickLogic emulator test package was replaced because the AVD data volume was 94% full. No other package or AVD content was removed, and no physical-device command or media access was used.
- PR #24 validation left the 94%-full existing AVD untouched and created an isolated API 36 x86_64 AVD from the already-installed TTDT system image. The 65,087,894-byte CI APK matched SHA-256 `1631d234...d21ab`, was v2-signed, and cold-launched in 10.865 seconds on first boot and 5.846 seconds after force-stop.
- With zero media grants, a metadata search created the 45,056-byte app-private `no_backup/picklogic-index.sqlite3`; a cold restart reopened it. Safe Mode, Storage Insight, SQLite recovery wording, and the Android access limitation rendered; fatal-log matches were zero.
