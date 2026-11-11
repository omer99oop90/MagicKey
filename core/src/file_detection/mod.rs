//! File Detection Engine module.

pub mod bom;
pub mod detector;
pub mod signature;
pub mod text_sniff;

pub use bom::{detect_bom, BomType};
pub use detector::{DetectionConfidence, DetectionMethod, DetectionResult, FileDetector};
pub use signature::{match_pattern, MagicPattern, SignatureDb, SignatureEntry};
pub use text_sniff::{analyze_text_content, TextAnalysis, TextSubType};
