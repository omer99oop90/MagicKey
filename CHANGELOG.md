# Changelog

All notable changes to the Magic Key project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0-alpha.6] — 2026-11-12

### Fixed & Enhanced (Phase 2.3.2: UTF-8 Boundary Correction)
- **UTF-8 Truncation Boundary Preservation (`app/lib/models/file_source.dart`):**
  - Implemented `findUtf8SafeLength(bytes, isTruncated)` to detect and exclude incomplete trailing 2-byte (Arabic), 3-byte (Euro/symbols), and 4-byte (emojis) UTF-8 sequences when reading reaches the 1 MB buffer boundary.
  - Guarantees complete UTF-8 characters are preserved without generating false replacement characters (`U+FFFD`) merely because the read limit split a character.
  - Genuinely malformed UTF-8 sequences within the stream body remain correctly flagged with `U+FFFD`.
- **Memory Ceiling Preservation & Zero-OOM Streaming:**
  - Maintained strict $O(1)$ memory limits ($< 1.05$ MB peak buffer) while accurately detecting whether a file exceeded the 1 MB reading threshold via bounded probing.
- **Text Viewer Truncation Notice Banner & Toolbar Badge (`app/lib/viewers/text_code_viewer.dart`):**
  - Added `TextContent` model carrying `isTruncated` and `bytesRead` metadata to viewer consumers.
  - Added amber truncation notice banner below the top toolbar indicating: *"File exceeds 1 MB reading limit. Displaying initial section ({size} total)."*
  - Added a visual `"1 MB Limit"` pill badge in the viewer toolbar next to line counts.
- **Exhaustive Unit Test Suite (`app/test/models_and_logic_test.dart`):**
  - Replaced weak boundary test with rigorous deterministic assertions verifying exact decoded outputs for Arabic 2-byte, 3-byte, and 4-byte UTF-8 characters.
  - Validated all boundary split permutations (1/2, 1/3, 2/3, 1/4, 2/4, 3/4) produce clean text with zero `U+FFFD`.
  - Validated files ending exactly at the reading boundary decode 100% of bytes without data loss.

## [0.1.0-alpha.5] — 2026-11-12

### Fixed & Enhanced (Phase 2.3: Core File Opening Validation)
- **UTF-8 Multi-byte Decoding & International Text Support (`app/lib/models/file_source.dart`):**
  - Replaced flawed `String.fromCharCodes` byte-to-UTF-16 conversion with `utf8.decode(chunk, allowMalformed: true)` in both `LocalPathFileSource` and `AndroidUriFileSource`.
  - Accurately renders Arabic, Unicode, and international multi-byte text files in the virtualized text viewer without mojibake or crashes.
  - Hardened file source reading methods (`readHeader`, `readChunk`) with defensive try/catch blocks.
- **Interactive Category Filtering via Android SAF (`app/lib/widgets/category_grid.dart` & `MainActivity.kt`):**
  - Transformed static category container cards into interactive touch targets using `Material` + `InkWell` ripple animations.
  - Connected category card taps directly to `FileService.pickFile(mimeType: item.mimeType)`.
  - Updated Android `MainActivity.kt` to extract the `mimeType` argument and configure `Intent.type` and `Intent.EXTRA_MIME_TYPES`, enabling targeted file pickers for images (`image/*`) and text/code (`text/*`).
  - Added full dynamic bidirectional localization (Arabic RTL & English LTR) to category cards.
- **Honest Phase 2 Category Badges:**
  - Updated category format hints across all 6 cards to accurately reflect active Phase 2 viewer capabilities versus Phase 3 roadmap engines:
    - *Document:* `Plain Text (PDF: Raw Hex)`
    - *Image:* `PNG, JPEG, WebP, SVG, GIF` (Active Viewer)
    - *Audio & Video:* `Audio & Video (Raw Hex / Phase 3)`
    - *Text & Code:* `Source Code, JSON, XML, MD` (Active Viewer)
    - *Archive:* `ZIP, APK, TAR (Raw Hex / Phase 3)`
    - *Binary & Other:* `Hex Engine, Byte Inspection` (Active Viewer)
- **APK Package Recognition in Rust Format Registry (`core/` & `signatures.json`):**
  - Added `"apk"` and `"jar"` to the known extensions list for the `zip` format in `file_detection/signatures.json` and `core/src/format_registry/registry.rs`.
  - Android application packages (`.apk`) are now recognized as valid ZIP packages without triggering false "Format Mismatch" warnings.
  - Added integration test `test_magic_bytes_detection_standard_formats` verification for `.apk` hints in `core/tests/detection_tests.rs`.
- **Defensive Error Containment & IO Exception Propagation:**
  - Wrapped `FileService.identifyFile()` in defensive try/catch returning safe fallback `DetectionResult` on stream read errors.
  - Hardened `readChunk()` to propagate OS `PlatformException` (IO_ERROR, permission denial) to viewer engines rather than swallowing errors as empty files, allowing `TextCodeViewer`, `ImageViewer`, and `HexViewer` retry error UIs to properly activate.
  - Added empty-stream guard in `readText()` to reject zero-byte streams when expected size > 0.
  - Wrapped `HomeScreen._openFile()` in defensive try/catch with snackbar feedback.

## [0.1.0-alpha.4] — 2026-11-11

### Added
- **Committed Android Project as Source of Truth (`app/android/`):**
  - Downloaded and committed official Gradle 8.4 wrapper (`gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle-wrapper.properties`).
  - Added complete Android AAPT resource directory (`app/android/app/src/main/res/`) providing:
    - `values/styles.xml` & `values-night/styles.xml` defining `LaunchTheme` and `NormalTheme`.
    - `values/colors.xml` and vector `drawable/ic_launcher_foreground.xml`.
    - Vector adaptive icon `mipmap-anydpi-v26/ic_launcher.xml` and density-specific PNG launcher icons (`mipmap-mdpi/`, `hdpi/`, `xhdpi/`, `xxhdpi/`, `xxxhdpi/`).
  - Completely removed `flutter create` and directory deletion from CI/CD workflow (`.github/workflows/build_apk.yml`), ensuring the committed repository is built with 100% fidelity.
- **Rust Dart:FFI Live Runtime Verification:**
  - Added `getRegistry()` method to `CoreBindings` exposing `magickey_get_registry_json`.
  - Added `app/test/ffi_runtime_test.dart` to execute live dynamic library loading and Rust core functions (`detectBuffer`, `formatHexChunk`, `getRegistry`) during CI `flutter test`.
  - Audited memory ownership, pointer lengths, and guaranteed single-release via `magickey_free_string`.
- **Release ARM64 Android APK Production:**
  - Successfully compiled `app-release.apk` directly from committed project in GitHub Actions ([Run #43069038389](https://github.com/omer99oop90/MagicKey/actions/runs/43069038389)).
  - Verified SHA-256 checksum: `01bea0ec98df88de9a935d3098bb27dfe6e926589fb50ee4b86f47afa50a15a4`.
  - Confirmed bundled `lib/arm64-v8a/libmagickey_core.so` (807,176 bytes) inside the APK.

## [0.1.0-alpha.3] — 2026-11-11

### Added
- **Remote Build & CI/CD Pipeline (`.github/workflows/build_apk.yml`):**
  - Fully automated GitHub Actions workflow to build the production ARM64 Android APK.
  - Matrix / runner execution on `ubuntu-latest` with Java 17, Rust stable toolchain (`dtolnay/rust-toolchain@stable`), and Flutter SDK 3.24.3 (`subosito/flutter-action@v2`).
  - Automated execution of Rust core unit/integration tests and Flutter unit tests.
  - Automatic packaging and upload of `app-release.apk` as a workflow artifact.
- **Android Gradle Build Infrastructure (`app/android/`):**
  - Added standard Android Gradle configuration (`settings.gradle`, root `build.gradle`, `app/build.gradle`, `gradle.properties`, and `gradle-wrapper.properties`).
  - Configured `namespace "com.magickey.app"` and `applicationId "com.magickey.app"` targeting Android SDK 34 (compileSdk 34, targetSdk 34, minSdk 21).
  - Explicitly mapped `jniLibs.srcDirs = ['src/main/jniLibs']` to package native ARM64 library into the APK.
- **Rust FFI Native Packaging (`app/android/app/src/main/jniLibs/arm64-v8a/`):**
  - Packaged compiled ELF64 AArch64 `libmagickey_core.so` (789 KB) directly into the Android app's `jniLibs/arm64-v8a/`.
  - Verified 100% Android Bionic runtime compatibility with dynamic dependencies strictly confined to system libraries `libc.so` and `libdl.so`.
  - Verified all 6 exported C symbols (`magickey_detect_file`, `magickey_detect_buffer`, `magickey_read_hex_chunk`, `magickey_format_hex_chunk`, `magickey_get_registry_json`, `magickey_free_string`).
- **Flutter Project Validation & Dependencies:**
  - Added `ffi: ^2.1.3` to `app/pubspec.yaml` dependencies.
  - Mirrored branding and category Lucide SVGs into `app/assets/` to satisfy Flutter package asset resolution.
  - Implemented standard `package:flutter_test` unit tests in `app/test/models_and_logic_test.dart`.
- **Android Intent Integration Hardening:**
  - Extended `MainActivity.kt` with `ACTION_SEND_MULTIPLE` intent handler for graceful handling of multi-file share payloads.
  - Added `contentResolver.takePersistableUriPermission()` to maintain persistent access across app sessions for files selected via SAF.
- **Verification Suite Expansion (`scripts/run_phase2_verification.py`):**
  - Expanded automated verification harness to audit jniLibs packaging, ELF symbols, Gradle scaffolding, and GitHub Actions workflow configuration.

## [0.1.0-alpha.2] — 2026-11-11

### Added
- **Flutter Application Shell & UI Architecture (`app/`):**
  - Production-ready Flutter structure configured with `pubspec.yaml`, assets declaration, and Material 3 design system.
  - Bidirectional localization (`app/lib/l10n/app_localizations.dart`) supporting full Arabic (RTL) and English (LTR).
  - Minimal modern theme system (`app/lib/theme/app_theme.dart`) with Light Mode (`#F8FAFC`) and Dark Mode (`#020617`).
- **Home Screen (`app/lib/screens/home_screen.dart`):**
  - Minimal branding with `magic-key.svg` vector asset.
  - Prominent "Open File" primary action button triggering Android Storage Access Framework.
  - Supported categories grid with Lucide SVG iconography (`assets/icons/*.svg`).
  - In-memory recent files tracking with quick-reopen capability and session clearance.
  - Interactive language toggle (العربية / English) and theme mode toggle (Light / Dark).
- **Universal Viewer Screen (`app/lib/screens/viewer_screen.dart`):**
  - Top navigation bar showing file title, detected format badge, formatted file size, and close button.
  - Format Mismatch Notice banner (`DiagnosticBanner`) for corrupted or misnamed files.
  - Toggle between rich graphical viewing and raw Hex Viewer inspection.
- **Initial Viewer Implementations (`app/lib/viewers/`):**
  - `TextCodeViewer`: Virtualized scrolling text viewer with line numbers, word-wrap toggle, and 1 MB memory ceiling.
  - `HexViewer`: Virtualized 16-byte chunk viewer connected to the Rust core via `dart:ffi`, supporting paging (256 B / page) and jump-to-offset navigation.
  - `ImageViewer`: Interactive 2D pan and pinch-to-zoom (0.5x to 10.0x) for raster images (PNG, JPEG, WebP, GIF, BMP, AVIF) and standalone SVGs via `flutter_svg`.
  - `UnsupportedViewer`: Explanatory fallback state with one-tap transition to the Hex Viewer.
- **Android System Integration (`app/android/`):**
  - Configured `AndroidManifest.xml` with intent filters for `ACTION_MAIN` (launcher), `ACTION_VIEW` (`*/*`), `ACTION_SEND`, and `ACTION_SEND_MULTIPLE`.
  - Implemented `MainActivity.kt` with `com.magickey/saf` MethodChannel providing `openDocument`, `readUriHeader`, `readUriChunk`, `getInitialIntentUri`, and `getMetadata`.
  - Decoupled `FileSource` abstraction (`AndroidUriFileSource` and `LocalPathFileSource`) allowing transparent reading from ContentResolver streams without raw filesystem path assumptions.
- **Dart:FFI Native Bridge (`app/lib/ffi/core_bindings.dart`):**
  - Zero-copy native bridge binding `libmagickey_core.so` functions into typed Dart calls with safe memory deallocation.
  - Added `magickey_format_hex_chunk` to Rust core and FFI exports, allowing in-memory byte buffer formatting for Android `content://` streams.
- **Verification Harness (`scripts/run_phase2_verification.py`):**
  - Automated 4-tier verification suite validating Rust core tests, C-ABI FFI boundary, Android Manifest/SAF Kotlin methods, and Flutter component/asset integrity.

## [0.1.0-alpha.1] — 2026-11-11

### Added
- **Core Engine Implementation (`core/`):**
  - High-performance, memory-safe, portable core implemented in Rust 1.99.1 (`aarch64-linux-android`).
  - Dual build artifacts: standalone Rust library (`rlib`), C-compatible dynamic library (`cdylib` / `libmagickey_core.so`), and command-line utility (`magickey_cli`).
- **File Detection Engine (`file_detection/`):**
  - Multi-stage pipeline: BOM detection -> Magic Bytes inspection -> Bounded text analysis -> Extension secondary hints -> Unknown binary fallback.
  - Byte Order Mark sniffer for UTF-8 (`EF BB BF`), UTF-16LE (`FF FE`), UTF-16BE (`FE FF`), UTF-32LE (`FF FE 00 00`), and UTF-32BE (`00 00 FE FF`).
  - Bounded content analyzer distinguishing plain text/code from binary (null byte analysis, control character ratio, UTF-8 validity).
  - Specialized text subtype detection for JSON, XML, HTML, SVG, Markdown, and Shell scripts.
  - Curated database (`file_detection/signatures.json`) expanded to support PDF, PNG, JPEG, GIF, WebP, BMP, AVIF, ZIP, GZIP, TAR, 7z, BZ2, MP4, MKV/WebM, MP3, WAV, FLAC, OGG, SQLite, ELF, Dalvik DEX, Java Class, and Windows PE binaries.
  - Strict security guarantee: Extensions are treated strictly as secondary hints and never trusted when magic bytes are absent or mismatched.
- **Format Registry (`format_registry/`):**
  - Centralized format repository indexing 39 standard file formats across 6 categories (`Document`, `Image`, `Media`, `TextCode`, `Archive`, `Binary`).
  - Decoupled detection logic from viewer routing with `resolve_viewer()`.
  - Case-insensitive lookups by format ID, MIME type, and extension.
- **Hex Viewer Engine (`engines/hex/`):**
  - Incremental, virtualized stream reader implementing canonical 16-byte aligned row formatting (`OFFSET  HEX_BYTES  |ASCII|`).
  - Strictly chunked reading with bounded memory allocation ($O(1)$ RAM usage, independently of file size).
  - Comprehensive boundary handling for empty files (0 bytes), partial terminal rows, and seeks past EOF.
- **C-ABI Foreign Function Interface (`core/src/ffi.rs`):**
  - Exported C symbols (`magickey_detect_file`, `magickey_detect_buffer`, `magickey_read_hex_chunk`, `magickey_get_registry_json`, `magickey_free_string`) enabling direct `dart:ffi` integration.
- **Automated Verification Harness (`scripts/run_phase1_tests.py`):**
  - 15 Cargo unit and integration tests covering detection, hex streaming, and registry routing.
  - 22 end-to-end fixture and C-ABI FFI tests using synthetic test vectors.
  - 100% test pass rate with zero clippy or rustfmt warnings.

## [0.1.0-alpha.0] — 2026-11-11

### Added
- **Project Foundation:** Established Magic Key project directory inside Android internal shared storage at `/storage/emulated/0/ANTYEE/MagicKey/`.
- **Environment Inspection & Hardware Profiling:**
  - Audited Termux host environment: Android 13 (`API 33`), Kernel 4.19.113 (`aarch64-linux-android`), 10.6 GB RAM.
  - Audited Ubuntu 26.04 PRoot container and compiler toolchains.
  - Documented critical storage boundary (3.8 GB available on `/dev/block/sda37` / 100% full).
  - Validated Android FUSE filesystem attributes (symlink restrictions, synthetic `noexec` permission behavior).
  - Confirmed available build tools: Git `2.56.0`, Rust & Cargo `1.99.1`, Clang `21.1.8`, OpenJDK `21.0.13`, Python `3.14.10`, Android `aapt`, `apksigner`, `zipalign`.
- **Technical Verification & Hardware Clarification Audit:**
  - Re-audited hardware: Confirmed `10,601.6 MiB` usable Linux RAM from 12 GB physical chip, `4,096.0 MiB` zRAM swap, and dynamic storage fluctuation between 3.86 GiB and 11.12 GiB on `/dev/block/sda37`.
  - Audited Git failure: Identified initial `git commit` exit code 128 caused by unset author identity (`u0_a604@localhost.(none)`), resolved via repository-local configuration.
  - Preserved project directory skeleton across all 18 module directories using `.gitkeep`.
  - Clarified Flutter SDK readiness: Confirmed Flutter SDK and Dart are not installed locally and that Flutter cannot compile APKs directly on an Android host; APK compilation is strictly targeted to CI/CD or desktop workstations while pure format logic remains locally testable.
  - Established concrete numerical security thresholds: 100:1 Zip-bomb ratio, 50 MB single-entry extraction cap, 10,000 archive entry cap, and 20 MB text highlight streaming limit.
- **Master Technical Blueprint (`PROJECT_BLUEPRINT.md`):**
  - Defined core mission: *Select a file. Identify it. Open it.*
  - Enforced strict anti-scope boundaries (no file manager, editor, converter, cloud platform, AI, or app launcher).
  - Evaluated candidate technologies and selected minimal viable technology stack (Flutter/Dart UI, native OS decoders, pure format detection, virtualized streaming Hex engine).
  - Established 5 core architectural principles: Inspection Precedes Rendering, Lazy Initialization, Fault Containment, Zero-Copy Streaming, Strict Local Isolation.
  - Outlined comprehensive security, threat model, and privacy guarantees.
- **System Architecture Specification (`ARCHITECTURE.md`):**
  - Defined 5-layer decoupled architecture: UI Layer, Application Core Layer, Detection & Registry Layer, Engine Router & Viewing Engines Layer, Platform Abstraction Layer.
  - Formulated multi-stage file detection pipeline (Magic Bytes Sniffing -> Text/Encoding Sniffing -> Syntax Token Sniffing -> Extension Heuristic -> Universal Octet-Stream Fallback).
  - Formulated Format Registry model and file category taxonomy.
  - Engineered Engine Router with defensive crash containment and automatic Hex fallback.
  - Detailed viewing engine specifications (Document, Image, Media, Text/Code, Archive, Hex).
  - Designed end-to-end data flow with Mermaid sequence diagrams.
- **Implementation Roadmap (`ROADMAP.md`):**
  - Structured 6-phase roadmap from Inception (Phase 0) to Security Hardening & Release Packaging (Phase 5).
  - Outlined explicit acceptance criteria and deliverables for each milestone.
- **Licenses & Third-Party Audit (`LICENSES.md`):**
  - Selected Apache 2.0 license for Magic Key.
  - Audited licenses for Flutter/Dart (BSD-3), Lucide Icons (ISC), and Android Native APIs (Apache 2.0).
- **Directory Layout:**
  - Initialized modular hierarchy: `app/`, `core/`, `file_detection/`, `format_registry/`, `engines/`, `platform/`, `assets/`, `tests/`, `docs/`, `scripts/`.
- **Automation & Tooling:**
  - Created automated environment audit script `scripts/verify_environment.py`.
