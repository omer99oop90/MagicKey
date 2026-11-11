# Third-Party Licenses & Intellectual Property Compliance

> **Project:** Magic Key  
> **Primary License:** Apache License, Version 2.0  
> **Workspace Path:** `/storage/emulated/0/ANTYEE/MagicKey/LICENSES.md`  

---

## 1. Project License

Magic Key is released under the **Apache License, Version 2.0**.

```text
Copyright 2026 Magic Key Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

## 2. Third-Party Dependency Audit

To maintain legal clarity and ensure barrier-free multiplatform distribution, Magic Key enforces a strict open-source licensing policy:
* **Allowed Licenses:** Permissive licenses only (**MIT**, **Apache 2.0**, **BSD-2-Clause**, **BSD-3-Clause**, **ISC**, **Unlicense**).
* **Restricted / Forbidden Licenses:** Viral copyleft licenses (**GPL v2/v3**, **AGPL**, **LGPL with static linking**) are strictly forbidden in client-distributed binaries unless runtime dynamic linking compliance is mathematically proven and authorized by architectural review.

### Audit Matrix of Core Dependencies & Candidates

| Component / Library | Proposed Role | License | Permissibility | Compliance Requirements |
|---|---|---|---|---|
| **Flutter SDK** | UI Framework & Engine | BSD 3-Clause | Allowed | Retain BSD copyright notice in distribution. |
| **Dart SDK** | Language Runtime & Core Libs | BSD 3-Clause | Allowed | Retain BSD copyright notice in distribution. |
| **Lucide Icons** | SVG UI & Category Iconography | ISC License | Allowed | Include ISC attribution notice with asset distribution. |
| **Android Open Source Project (AOSP)** | Native APIs (`PdfRenderer`, `MediaCodec`) | Apache 2.0 | Allowed | Built into host OS. No extra binary distribution needed. |
| **`archive` (Dart)** | ZIP / TAR / GZ Safe Parsing | Apache 2.0 | Allowed | Standard Apache notice retention. |
| **`flutter_highlight`** | Virtualized Syntax Tokenizer | MIT License | Allowed | Retain MIT notice and permission block. |
| **`flutter_svg`** | Vector Icon Rendering Engine | MIT License | Allowed | Retain MIT notice in compiled app credits. |
| **Rust Standard Library** | Native Rust Core Integration | MIT / Apache 2.0 | Allowed | Dual-licensed permissive; fully compliant. |
| **FFmpeg (Candidate)** | Audio/Video Decoder | LGPL 2.1+ / GPL | **REJECTED (v0.1)** | Rejected due to binary bloat (~40MB) and copyleft compliance risk. Native MediaCodec used instead. |
| **LibreOffice (Candidate)**| Office Document Rendering | MPL 2.0 / LGPL | **REJECTED (v0.1)** | Rejected due to extreme size (>200MB) and licensing complexity. |

---

## 3. Dependency Licensing Checklist

Before adopting any third-party crate, package, or asset into Magic Key:
1. [ ] Verify that the license is approved (MIT, Apache 2.0, BSD, or ISC).
2. [ ] Verify that no transitive dependency introduces copyleft obligations.
3. [ ] Add attribution text and copyright notices to the in-app `About & Licenses` dialog.
4. [ ] Ensure no proprietary or non-commercial (CC-BY-NC) assets are included.
