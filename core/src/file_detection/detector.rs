//! Multi-stage File Detection Pipeline.

use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{self, Read};
use std::path::Path;

use super::bom::detect_bom;
use super::signature::{match_pattern, SignatureDb};
use super::text_sniff::{analyze_text_content, TextSubType};
use crate::format_registry::{FileCategory, FormatRegistry, ViewerEngine};

/// Confidence level of the format detection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DetectionConfidence {
    Unknown = 0,
    Low = 1,
    Medium = 2,
    High = 3,
}

impl std::fmt::Display for DetectionConfidence {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::High => write!(f, "High"),
            Self::Medium => write!(f, "Medium"),
            Self::Low => write!(f, "Low"),
            Self::Unknown => write!(f, "Unknown"),
        }
    }
}

/// The detection technique that positively identified or classified the format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DetectionMethod {
    MagicBytes,
    Bom,
    TextContent,
    ExtensionFallback,
    UnknownBinary,
}

impl std::fmt::Display for DetectionMethod {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MagicBytes => write!(f, "Magic Bytes Inspection"),
            Self::Bom => write!(f, "Byte Order Mark (BOM)"),
            Self::TextContent => write!(f, "Text Content Analysis"),
            Self::ExtensionFallback => write!(f, "Extension Fallback (Verified Text)"),
            Self::UnknownBinary => write!(f, "Unclassified Binary Stream"),
        }
    }
}

/// Structured format identification result.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DetectionResult {
    pub format_id: String,
    pub display_name: String,
    pub mime_type: String,
    pub category: FileCategory,
    pub confidence: DetectionConfidence,
    pub detection_method: DetectionMethod,
    pub suggested_viewer: ViewerEngine,
    pub details: String,
}

/// Core multi-stage file detection engine.
pub struct FileDetector {
    db: SignatureDb,
    registry: FormatRegistry,
}

impl Default for FileDetector {
    fn default() -> Self {
        Self::new()
    }
}

impl FileDetector {
    /// Creates a detector initialized with embedded signatures and the default format registry.
    pub fn new() -> Self {
        let db = SignatureDb::load_embedded().unwrap_or_else(|e| {
            eprintln!("[WARN] MagicKey: Embedded signatures failed to load: {}", e);
            SignatureDb {
                version: "empty".into(),
                signatures: Vec::new(),
            }
        });
        Self {
            db,
            registry: FormatRegistry::default(),
        }
    }

    /// Creates a detector with an explicit signature database and registry.
    pub fn with_custom(db: SignatureDb, registry: FormatRegistry) -> Self {
        Self { db, registry }
    }

    /// Access the underlying format registry.
    pub fn registry(&self) -> &FormatRegistry {
        &self.registry
    }

    /// Identifies the format of a file from its path. Reads up to 512 bytes bounded.
    pub fn detect_file(&self, path: &Path) -> io::Result<DetectionResult> {
        let mut file = File::open(path)?;
        let mut buffer = [0u8; 512];
        let bytes_read = file.read(&mut buffer)?;
        let header = &buffer[..bytes_read];

        let ext = path.extension().and_then(|e| e.to_str());

        // TAR check: POSIX tar header magic 'ustar' is at offset 257.
        // If file has >= 512 bytes, offset 257 is already in header.
        Ok(self.detect_buffer(header, ext))
    }

    /// Identifies format from a raw header slice and optional file extension hint.
    pub fn detect_buffer(&self, header: &[u8], extension_hint: Option<&str>) -> DetectionResult {
        let ext_normalized = extension_hint.map(|e| e.trim_start_matches('.').to_ascii_lowercase());

        // 1. Handle Empty File
        if header.is_empty() {
            return DetectionResult {
                format_id: "empty".into(),
                display_name: "Empty File".into(),
                mime_type: "inode/x-empty".into(),
                category: FileCategory::Unknown,
                confidence: DetectionConfidence::High,
                detection_method: DetectionMethod::TextContent,
                suggested_viewer: ViewerEngine::Hex,
                details: "File contains 0 bytes.".into(),
            };
        }

        // 2. Stage 1: Detect Unicode Byte Order Mark (BOM)
        if let Some(bom) = detect_bom(header) {
            let details = format!("Detected {}", bom.encoding_label());
            // If an extension exists that is a known text/code format, refine it
            if let Some(ext) = &ext_normalized {
                if let Some(def) = self.registry.get_by_extension(ext) {
                    if def.category == FileCategory::TextCode {
                        return DetectionResult {
                            format_id: def.id.clone(),
                            display_name: def.display_name.clone(),
                            mime_type: def.mime_type.clone(),
                            category: def.category,
                            confidence: DetectionConfidence::High,
                            detection_method: DetectionMethod::Bom,
                            suggested_viewer: def.recommended_viewer,
                            details: format!(
                                "{}. Refined via valid extension '.{}'.",
                                details, ext
                            ),
                        };
                    }
                }
            }
            return DetectionResult {
                format_id: "text".into(),
                display_name: "Plain Text Document".into(),
                mime_type: "text/plain".into(),
                category: FileCategory::TextCode,
                confidence: DetectionConfidence::High,
                detection_method: DetectionMethod::Bom,
                suggested_viewer: ViewerEngine::TextCode,
                details,
            };
        }

        // 3. Stage 2: Check Magic Bytes in Database
        for sig in &self.db.signatures {
            for pattern in &sig.magic {
                if match_pattern(pattern, header) {
                    // Match found! Look up full definition in FormatRegistry
                    if let Some(def) = self.registry.get_by_id(&sig.id) {
                        return DetectionResult {
                            format_id: def.id.clone(),
                            display_name: def.display_name.clone(),
                            mime_type: def.mime_type.clone(),
                            category: def.category,
                            confidence: DetectionConfidence::High,
                            detection_method: DetectionMethod::MagicBytes,
                            suggested_viewer: def.recommended_viewer,
                            details: format!("Positively identified via primary magic byte signature (offset {}).", pattern.offset),
                        };
                    } else {
                        // Fallback from raw signature entry
                        let category = match sig.category.as_str() {
                            "document" => FileCategory::Document,
                            "image" => FileCategory::Image,
                            "media" => FileCategory::Media,
                            "archive" => FileCategory::Archive,
                            "text_code" => FileCategory::TextCode,
                            _ => FileCategory::Binary,
                        };
                        let viewer = self.registry.resolve_viewer(&sig.id);
                        return DetectionResult {
                            format_id: sig.id.clone(),
                            display_name: sig.name.clone(),
                            mime_type: sig.mime.clone(),
                            category,
                            confidence: DetectionConfidence::High,
                            detection_method: DetectionMethod::MagicBytes,
                            suggested_viewer: viewer,
                            details: format!(
                                "Positively identified via signature database (offset {}).",
                                pattern.offset
                            ),
                        };
                    }
                }
            }
        }

        // 4. Stage 3: Bounded Text Content Inspection
        let analysis = analyze_text_content(header);
        if analysis.is_text {
            match analysis.sub_type {
                TextSubType::Svg => {
                    return DetectionResult {
                        format_id: "svg".into(),
                        display_name: "Scalable Vector Graphics".into(),
                        mime_type: "image/svg+xml".into(),
                        category: FileCategory::Image,
                        confidence: DetectionConfidence::High,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::Image,
                        details: "Verified XML text containing <svg> vector root element.".into(),
                    };
                }
                TextSubType::Json => {
                    return DetectionResult {
                        format_id: "json".into(),
                        display_name: "JavaScript Object Notation".into(),
                        mime_type: "application/json".into(),
                        category: FileCategory::TextCode,
                        confidence: DetectionConfidence::High,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::TextCode,
                        details: "Verified JSON structured text starting with object/array token."
                            .into(),
                    };
                }
                TextSubType::Html => {
                    return DetectionResult {
                        format_id: "html".into(),
                        display_name: "HyperText Markup Language".into(),
                        mime_type: "text/html".into(),
                        category: FileCategory::TextCode,
                        confidence: DetectionConfidence::High,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::TextCode,
                        details:
                            "Verified HTML document starting with <!DOCTYPE html> or <html> tag."
                                .into(),
                    };
                }
                TextSubType::Xml => {
                    return DetectionResult {
                        format_id: "xml".into(),
                        display_name: "Extensible Markup Language".into(),
                        mime_type: "application/xml".into(),
                        category: FileCategory::TextCode,
                        confidence: DetectionConfidence::High,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::TextCode,
                        details: "Verified XML document starting with <?xml declaration.".into(),
                    };
                }
                TextSubType::Markdown => {
                    return DetectionResult {
                        format_id: "markdown".into(),
                        display_name: "Markdown Document".into(),
                        mime_type: "text/markdown".into(),
                        category: FileCategory::TextCode,
                        confidence: DetectionConfidence::High,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::TextCode,
                        details: "Verified plain text containing Markdown headers or frontmatter."
                            .into(),
                    };
                }
                TextSubType::ShellScript => {
                    return DetectionResult {
                        format_id: "shell".into(),
                        display_name: "Shell Script".into(),
                        mime_type: "text/x-shellscript".into(),
                        category: FileCategory::TextCode,
                        confidence: DetectionConfidence::High,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::TextCode,
                        details: "Verified Unix executable script starting with #! shebang.".into(),
                    };
                }
                TextSubType::PlainText => {
                    // Check if an extension hint exists for specific source code / text formats
                    if let Some(ext) = &ext_normalized {
                        if let Some(def) = self.registry.get_by_extension(ext) {
                            if def.category == FileCategory::TextCode {
                                return DetectionResult {
                                    format_id: def.id.clone(),
                                    display_name: def.display_name.clone(),
                                    mime_type: def.mime_type.clone(),
                                    category: def.category,
                                    confidence: DetectionConfidence::Medium,
                                    detection_method: DetectionMethod::ExtensionFallback,
                                    suggested_viewer: def.recommended_viewer,
                                    details: format!("Verified valid text content; classified as {} via secondary extension hint '.{}'.", def.display_name, ext),
                                };
                            }
                        }
                    }
                    return DetectionResult {
                        format_id: "text".into(),
                        display_name: "Plain Text Document".into(),
                        mime_type: "text/plain".into(),
                        category: FileCategory::TextCode,
                        confidence: DetectionConfidence::Medium,
                        detection_method: DetectionMethod::TextContent,
                        suggested_viewer: ViewerEngine::TextCode,
                        details: "Verified printable text/code stream (0 null bytes, valid UTF-8)."
                            .into(),
                    };
                }
            }
        }

        // 5. Stage 4: Non-text binary data with no magic match
        // Note: Do not blindly trust file extension if magic bytes failed!
        if let Some(ext) = &ext_normalized {
            if let Some(def) = self.registry.get_by_extension(ext) {
                // If the extension claimed to be a format with well-known magic (e.g. PDF, PNG, JPEG),
                // but the magic bytes didn't match, explicitly report it as corrupted or misnamed!
                if def.category != FileCategory::TextCode {
                    return DetectionResult {
                        format_id: "unknown_binary".into(),
                        display_name: "Unrecognized Binary (Corrupted or Misnamed)".into(),
                        mime_type: "application/octet-stream".into(),
                        category: FileCategory::Binary,
                        confidence: DetectionConfidence::Unknown,
                        detection_method: DetectionMethod::UnknownBinary,
                        suggested_viewer: ViewerEngine::Hex,
                        details: format!("Extension indicates '.{}' ({}) but expected magic byte signatures were absent. Routing to Hex Viewer.", ext, def.display_name),
                    };
                }
            }
        }

        // 6. Stage 5: Universal Fallback -> Unknown Binary
        DetectionResult {
            format_id: "unknown_binary".into(),
            display_name: "Unknown Binary Data".into(),
            mime_type: "application/octet-stream".into(),
            category: FileCategory::Binary,
            confidence: DetectionConfidence::Unknown,
            detection_method: DetectionMethod::UnknownBinary,
            suggested_viewer: ViewerEngine::Hex,
            details: "Unclassified binary stream with no matching magic signature. Displaying via Hex Viewer.".into(),
        }
    }
}
