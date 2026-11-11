# Magic Key — Project Blueprint & Technical Foundation

> **Universal File Opener | Architecture, Specification, and Technical Strategy**  
> **Status:** Foundation Phase Complete  
> **Target Release:** v0.1.0 (MVP)  
> **Location:** `/storage/emulated/0/ANTYEE/MagicKey/`  

---

## 1. Project Identity & Mission

### 1.1 Core Mission
**Magic Key** is a lightweight, modern, cross-platform universal file opener built on a single, uncompromising principle:

> **Select any file, automatically identify its actual format, choose the appropriate viewing engine, and display its contents whenever technically possible.**

### 1.2 Anti-Scope Boundaries
Magic Key is strictly an inspection and viewing tool. To preserve extreme speed, minimal binary size, and rock-solid stability, the application explicitly rejects scope creep:

| Excluded Role | Rationale |
|---|---|
| **No File Manager** | Magic Key does not organize, copy, cut, delete, rename, or batch-manage files. |
| **No File Editor** | Files are opened strictly in read-only mode. No modification, saving, or metadata stripping. |
| **No File Converter** | No transcoding, export transforms, or file type conversion routines. |
| **No App Launcher** | It does not act as an Android intent dispatcher or desktop file launcher. |
| **No Cloud Platform** | Zero cloud synchronization, zero remote accounts, zero server dependencies. |
| **No AI Assistant** | No heavy embedded LLMs, no remote inference queries, no summarization bloat. |

---

## 2. Environment Inspection & Hardware Constraints

An empirical audit of the host environment was performed directly on the target hardware before establishing any architectural patterns.

### 2.1 Host Environment Characteristics
* **Host Platform:** Android 13 (API level 33), Linux Kernel 4.19.113 (`aarch64-linux-android`).
* **RAM Profile:** Total 10,601 MB (~10 GB), Available ~2,911 MB, Swap 4,095 MB (~4 GB).
* **Storage Profile:**
  * Root Mount (`/dev/block/sda37` mapped to `/data` and `/storage/emulated`): 465 GB Total, 461 GB Used, **3.8 GB Available (100% full)**.
  * **Critical Constraint:** Extreme storage pressure. Dependencies must be lightweight; heavy multi-gigabyte SDKs (e.g. monolithic Android Studio distributions or unneeded toolchains) cannot be installed locally without risking device exhaustion.
* **Shared Storage Quirks (`/storage/emulated/0` FUSE):**
  * Android's FUSE emulation forbids symbolic link creation (`ln -s` returns `Permission denied`).
  * Direct execution permissions (`chmod +x`) are synthetic and masked (`noexec` attribute). Build scripts and test runners must be executed via direct interpreter calls (e.g., `python3 script.py`, `bash script.sh`).
  * Git repositories function normally over FUSE without index corruption.

### 2.2 Toolchain Availability Audit

| Tool | Termux (Host) | Ubuntu (PRoot Container) | Status & Architectural Role |
|---|---|---|---|
| **Git** | `2.56.0` | `2.53.0` | Installed & verified on shared storage. |
| **Rust / Cargo** | `1.99.1` (`aarch64-linux-android`) | Available via host path | Native host compiler available; produces Android ARM64 ELFs. |
| **Clang / C++** | `21.1.8` | Available via host path | System C/C++ compiler targeting Bionic libc. |
| **Java (JDK)** | OpenJDK `21.0.13` (`javac`, `java`) | OpenJDK `21.0.13` | Available for Android dexing and build tools. |
| **Python** | `3.14.10` | `3.14.4` | Environment scripting, format testing, code generation. |
| **Android Packaging** | `aapt`, `apksigner`, `zipalign` | Shared from Termux | APK resource packaging and alignment functional. |
| **DEX Compiler** | `d8` / `dx` (in Termux repo) | `d8` via apt | Dex bytecode compilation available without full studio. |
| **Flutter / Dart** | Dart in Termux repo; Flutter via workstation/CI | Available for headless Dart | Flutter app shell designed for cross-platform portability. |

---

## 3. Technology Selection & Justification

To ensure maximum performance and cross-platform longevity without bloating memory or storage:

### 3.1 Primary UI Framework: Flutter & Dart
* **Selection:** Flutter (Dart 3.x) with strict decoupling between UI widgets and the core format engines.
* **Justification:**
  * Native rendering via Impeller/Skia across Android, iOS, Windows, macOS, Linux, and Web.
  * Built-in support for responsive layout and bidirectional text (Arabic RTL and English LTR).
  * Declarative, reactive UI that renders high-frame-rate viewports with minimal memory footprint.
  * Clear architectural boundaries: Core format detection and parsing logic can run in pure Dart or Rust, decoupled from the UI layer.

### 3.2 Core & Native Integration: Pure Portable Core + Rust FFI / Native Platform Channels
* **Selection:** Dual-tier core:
  1. High-speed pure Dart core for multiplatform zero-dependency execution (Web, Desktop, Mobile).
  2. Native Android APIs via Platform Channels / Rust FFI for platform-specific hardware acceleration.
* **Justification:** Avoids cross-compilation headaches across esoteric architectures while allowing high-performance native decoding where available.

### 3.3 Viewing Engine Matrix & Dependency Evaluation

| Category | Evaluated Candidates | Selected Solution | Justification |
|---|---|---|---|
| **Documents (PDF)** | PDFium vs Native `android.graphics.pdf.PdfRenderer` vs `pdfrx` | **Native `PdfRenderer` on Android; PDFium/pdf.js for Desktop/Web** | Android's built-in `PdfRenderer` has **0 MB added APK size** and hardware-accelerated page rendering. No ~25MB native PDFium binary needed for mobile. |
| **Images** | Bundled C decoders vs Native Platform Decoders | **Hardware-Accelerated Platform Codecs** | Android OS natively supports JPEG, PNG, GIF, WebP, BMP, HEIF, AVIF. Leverages OS hardware pipelines with zero binary bloat. |
| **Audio & Video** | FFmpeg vs Native MediaCodec / ExoPlayer / Media3 | **Native Media3 / ExoPlayer (Android) & AVPlayer (iOS)** | FFmpeg adds ~40 MB binary size and high battery consumption. Built-in OS media codecs cover standard formats (MP4, MKV, WebM, MP3, AAC, FLAC, WAV, OGG) with hardware decoding. |
| **Archives** | `libarchive` (C) vs Pure Dart `archive` / Rust `zip-rs` | **Pure Safe Streaming Reader (`archive` / Rust core)** | Zero external C shared libraries. Enforces strict zip-bomb limits (100:1 ratio cap) and path-traversal sanitization. |
| **Text & Code** | Tree-sitter vs Virtualized Stream Tokenizer (`flutter_highlight`) | **Virtualized Stream Reader + Lightweight Tokenizer** | Tree-sitter grammars consume 50MB+ compiled space. A virtualized syntax tokenizer handles 180+ languages with <1MB footprint and immediate startup. |
| **Unknown Binary** | Generic error vs Virtualized Hex Stream Viewer | **Custom Virtualized Hex Engine** | 16-byte aligned chunked reader (4KB-64KB pages). Displays Offset | Hex Bytes | ASCII. Can open a 10 GB file in <100ms using fixed 5 MB RAM. |

---

## 4. Architectural Principles

1. **Inspection Precedes Rendering:** Never blindly trust file extensions. Every file is piped through the Multi-Stage Detection Engine (Magic Bytes Sniffing -> Structure Validation -> Extension Fallback).
2. **Lazy Initialization:** Zero viewing engines are initialized at startup. Engines are instantiated only when the engine router commits to rendering the detected format.
3. **Fault Containment:** An engine error (e.g. malformed codec, corrupted header) must NEVER crash the application shell. Failed renders fall back gracefully to the Universal Hex Viewer with an explanatory diagnostic banner.
4. **Zero-Copy Streaming:** Large files are read via memory-mapped buffers or chunked streams. The memory consumption of Magic Key remains constant regardless of file size.
5. **Strict Local Isolation:** Magic Key makes zero network calls. No telemetry, no crash reporting beacons, no remote resource fetching.

---

## 5. Version 0.1 (MVP) Scope Matrix

```
[ Magic Key v0.1 MVP ]
├── Input Channels
│   ├── System File Picker (SAF / File Open Dialog)
│   └── Android Share Intent Receiver (ACTION_SEND / ACTION_VIEW)
├── Detection Engine
│   ├── Magic Bytes Signature Table (First 16 to 512 bytes)
│   ├── Text Encoding Sniffer (UTF-8, UTF-16LE/BE, ASCII)
│   └── MIME & Extension Heuristic Fallback
├── Viewer Engines
│   ├── Document: PDF (Hardware-accelerated native renderer)
│   ├── Image: PNG, JPEG, GIF, WebP, BMP, SVG, AVIF (Zoom/Pan)
│   ├── Media: MP4, MKV, WebM, MP3, AAC, WAV, FLAC, OGG (Playback controls)
│   ├── Text/Code: Markdown, JSON, XML, HTML, Rust, Dart, Python, C/C++, etc.
│   ├── Archive: ZIP, TAR, GZ (Safe tree explorer, entry inspection)
│   └── Universal Fallback: High-Performance Virtualized Hex Viewer
└── User Interface
    ├── Clean Minimal Home Screen (Magic Key branding, Open File, Category badges)
    ├── Responsive Viewer Shell (Top bar, File name, Format tag, Dynamic controls)
    └── Full RTL (Arabic) & LTR (English) localization
```

---

## 6. Security, Threat Model & Privacy Guarantees

Every file opened by Magic Key is treated as untrusted and potentially hostile:

1. **No Code Execution:** Executable files (`.dex`, `.apk`, `.elf`, `.exe`, `.so`, `.sh`) are recognized, categorized as Executable Binaries, and redirected to the **Hex Viewer** or metadata inspector. They are NEVER executed.
2. **Script & Macro Isolation:** Embedded JavaScript in PDFs or SVGs and macros in Office files are stripped or completely ignored by the viewing engines.
3. **Zip-Bomb & Decompression Traps:** Archive engines enforce a maximum decompression ratio of 100:1 and a single-file extraction limit (e.g., 50 MB in preview mode).
4. **Path Traversal Immunity:** Archive directory walks automatically strip prefix slashes (`/`), parent references (`../`), and drive indicators (`C:`).
5. **Memory Cap:** Viewing buffers enforce a hard cap per viewport chunk to avoid Out-Of-Memory (OOM) denial-of-service on rogue binary inputs.

---

## 7. Implementation Strategy

* **Phase 1 (Foundation & Core):** Multi-stage file detection engine, format registry, binary magic byte table, and universal hex engine.
* **Phase 2 (Application Shell & UI):** Minimal responsive Flutter UI, theme system (Light/Dark), bidirectional localization (Arabic RTL & English LTR), Lucide SVG icons.
* **Phase 3 (Viewer Engines):** Document, image, media, text/code, and archive viewer implementations.
* **Phase 4 (Platform & System Integration):** Android SAF, Share Intent handling, ContentResolver streaming, desktop drag-and-drop.
* **Phase 5 (Verification & Packaging):** Stress tests, malformed file fuzzing, CI/CD pipeline definition for cross-platform releases.
