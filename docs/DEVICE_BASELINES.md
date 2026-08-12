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
- Local Flutter plugin generation was blocked because Windows Developer Mode is off. VM heap evidence identified `MissingPluginException`; the candidate arm64 CI APK was separately checked and does contain both the bridge classes and generated registration call.
- The app now bounds bootstrap platform reads and shows a safe retryable error instead of an infinite Storage spinner when platform initialization fails.
