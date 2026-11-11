# Magic Key — Universal File Opener 🗝️

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSES.md)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Web-lightgrey.svg)](PROJECT_BLUEPRINT.md)
[![Status](https://img.shields.io/badge/Status-Foundation%20Phase%20Complete-brightgreen.svg)](ROADMAP.md)

> **Select a file. Identify it. Open it.**  
> A lightweight, modern, cross-platform universal file opener designed with single-purpose elegance.

---

## 📖 Overview

**Magic Key** solves a ubiquitous modern computing problem: you receive an arbitrary file on your device and just want to inspect what is inside without installing dozens of heavy, ad-ridden, or privacy-invasive applications.

Magic Key automatically inspects the file's raw magic bytes, determines its true format regardless of file extension, activates the optimal lightweight viewing engine, and renders its contents immediately.

### What Magic Key IS:
* A modern, hyper-focused universal file viewer.
* 100% offline, privacy-first, and lightweight.
* Equipped with intelligent format detection and a universal hex viewer fallback.

### What Magic Key IS NOT:
* ❌ Not a file manager (no copying, moving, renaming, or deleting).
* ❌ Not a file editor (strictly read-only inspection).
* ❌ Not a converter (no format transcoding).
* ❌ Not an application launcher.
* ❌ Not a cloud storage sync client.
* ❌ Not an AI assistant.

---

## 🚀 Key Features (v0.1 Minimal MVP)

1. **Intelligent Format Detection:** Multi-stage inspection pipeline using magic byte sniffing, structure validation, and text encoding heuristics.
2. **Document Viewer:** Hardware-accelerated PDF rendering via native OS engines.
3. **Image Viewer:** Full pan-and-zoom viewer for PNG, JPEG, GIF, WebP, BMP, SVG, and AVIF.
4. **Media Player:** Native hardware-accelerated playback for MP4, MKV, WebM, MP3, AAC, FLAC, WAV, and OGG.
5. **Text & Source Code Viewer:** High-performance virtualized stream viewer with syntax highlighting for 180+ programming and markup languages.
6. **Archive Tree Explorer:** Safe, read-only hierarchical browser for ZIP, TAR, and GZ archives with zip-bomb and path-traversal protection.
7. **Universal Hex Viewer Fallback:** Virtualized 16-byte aligned stream reader that can smoothly open multi-gigabyte binary files in under 100 milliseconds.
8. **Android System Integration:** Full support for Storage Access Framework (SAF) and Android Share Intents (`ACTION_SEND` and `ACTION_VIEW`).
9. **Modern Minimalist UI:** Clean Material 3 aesthetics with Light & Dark themes, Lucide SVG iconography, and complete bidirectional Arabic (RTL) and English (LTR) support.

---

## 📂 Project Directory Structure

```
MagicKey/
├── PROJECT_BLUEPRINT.md    # Master architecture, technical decisions, and strategy
├── ARCHITECTURE.md         # Detailed component specifications, data flow, and diagrams
├── ROADMAP.md              # Phased implementation plan, milestones, and acceptance criteria
├── README.md               # Project overview, setup, and developer guide
├── CHANGELOG.md            # Record of notable changes per release
├── LICENSES.md             # Third-party licensing audit and attribution guidelines
├── app/                    # Flutter application UI shell, themes, screens, and l10n
├── core/                   # Application core, file handling, session lifecycle, and state
├── file_detection/         # Magic byte signatures, sniffers, and format detection logic
├── format_registry/        # Format definitions, categories, and engine bindings
├── engines/                # Modular viewing engines:
│   ├── document/           # PDF and document viewing engine
│   ├── image/              # Hardware-accelerated image viewing engine
│   ├── media/              # Audio and video playback engine
│   ├── text_code/          # Virtualized text and syntax-highlighted code engine
│   ├── archive/            # Safe archive tree explorer and extractor
│   └── hex/                # Universal virtualized hex stream fallback engine
├── platform/               # Platform-specific OS adapters (Android SAF, Desktop, Web)
├── assets/                 # Icons (Lucide SVGs), branding, and format badges
├── tests/                  # Headless unit, integration, and security fuzz tests
├── docs/                   # Additional format specifications and security policies
└── scripts/                # Development, validation, and packaging automation scripts
```

---

## 🛠️ Development Environment & Setup

### Environment Requirements
* **Primary Host:** Android Termux (`aarch64-linux-android`) or any Linux / macOS / Windows workstation.
* **Compilers & Runtimes:**
  * Rust `1.80+` / Cargo (Host compiler installed)
  * Java JDK `21+` (`javac`, `java`)
  * Python `3.10+` (for scripts and validation test suites)
  * Flutter SDK `3.22+` / Dart `3.4+` (for application UI builds)

### Storage & Filesystem Notes (Android Shared Storage)
The project is officially located inside Android internal shared storage:
`/storage/emulated/0/ANTYEE/MagicKey/`

* Android's FUSE mount restricts symlink creation and sets a synthetic `noexec` permission bit.
* Always execute development scripts via their interpreter:
  ```bash
  python3 scripts/verify_environment.py
  ```

---

## 🧪 Running Verification & Tests

To verify that the development environment, storage permissions, and dependencies meet all architectural criteria, run the environment verification script:

```bash
cd /storage/emulated/0/ANTYEE/MagicKey
python3 scripts/verify_environment.py
```

---

## 📜 License & Acknowledgments

Magic Key is licensed under the [Apache License, Version 2.0](LICENSES.md).  
Icons courtesy of [Lucide Icons](https://lucide.dev) under the ISC License.
