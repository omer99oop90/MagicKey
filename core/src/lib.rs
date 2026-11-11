//! Magic Key Core Library
//! Universal File Opener format detection, format registry, and virtualized Hex viewer.

pub mod engines;
pub mod ffi;
pub mod file_detection;
pub mod format_registry;

pub use engines::hex::{format_row, HexChunk, HexEngine, HexRow};
pub use file_detection::{
    analyze_text_content, detect_bom, BomType, DetectionConfidence, DetectionMethod,
    DetectionResult, FileDetector, MagicPattern, SignatureDb, SignatureEntry, TextAnalysis,
    TextSubType,
};
pub use format_registry::{
    FileCategory, FormatDefinition, FormatRegistry, SupportStatus, ViewerEngine,
};

/// Convenience function to detect format from a path using default detector.
pub fn detect_file(path: impl AsRef<std::path::Path>) -> std::io::Result<DetectionResult> {
    let detector = FileDetector::new();
    detector.detect_file(path.as_ref())
}

/// Convenience function to detect format from an in-memory buffer.
pub fn detect_buffer(buffer: &[u8], extension_hint: Option<&str>) -> DetectionResult {
    let detector = FileDetector::new();
    detector.detect_buffer(buffer, extension_hint)
}
