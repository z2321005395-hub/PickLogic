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
- Build type: user.
- Security patch reported by device: 2025-11-01.
- Intended scale checks: about 17,895 images, 6,133 screenshots, and 5,618 camera images; these are user-provided planning figures until measured read-only.

No image metadata index or performance benchmark has been run yet.

## Local Android development toolchain

- Reused location: `%USERPROFILE%\Desktop\ttdt\toolchains` (local-only path; never emitted to public logs).
- Temurin JDK 17.0.19, Gradle 9.4.1, Android SDK Platform/Build Tools 36, Platform Tools 37.0.0, Emulator 36.6.11.
- Existing AVDs: one API 23 x86 legacy image and one API 36 x86_64 modern image.
- PickLogic tooling must consume this environment without modifying TTDT source or artifacts.
