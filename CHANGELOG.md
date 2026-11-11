# Changelog

All notable changes to the Magic Key project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0-alpha.0] — 2026-11-11

### Added
- **Project Foundation:** Established Magic Key project directory inside Android internal shared storage at `/storage/emulated/0/ANTYEE/MagicKey/`.
- **Environment Inspection & Hardware Profiling:**
  - Audited Termux host environment: Android 13 (`API 33`), Kernel 4.19.113 (`aarch64-linux-android`), 10.6 GB RAM.
  - Audited Ubuntu 26.04 PRoot container and compiler toolchains.
  - Documented critical storage boundary (3.8 GB available on `/dev/block/sda37` / 100% full).
  - Validated Android FUSE filesystem attributes (symlink restrictions, synthetic `noexec` permission behavior).
  - Confirmed available build tools: Git `2.56.0`, Rust & Cargo `1.99.1`, Clang `21.1.8`, OpenJDK `21.0.13`, Python `3.14.10`, Android `aapt`, `apksigner`, `zipalign`.
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
