# Changelog

All notable changes to the Magic Key project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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
