//! Data models for Magic Key Format Registry.

use serde::{Deserialize, Serialize};

/// High-level file categories supported by Magic Key.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FileCategory {
    Document,
    Image,
    Media,
    TextCode,
    Archive,
    Binary,
    Unknown,
}

impl std::fmt::Display for FileCategory {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Document => write!(f, "Document"),
            Self::Image => write!(f, "Image"),
            Self::Media => write!(f, "Audio/Video"),
            Self::TextCode => write!(f, "Text & Code"),
            Self::Archive => write!(f, "Archive"),
            Self::Binary => write!(f, "Binary"),
            Self::Unknown => write!(f, "Unknown"),
        }
    }
}

/// Dedicated viewer engines dispatched by the Engine Router.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ViewerEngine {
    Document,
    Image,
    Media,
    TextCode,
    Archive,
    Hex,
}

impl std::fmt::Display for ViewerEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Document => write!(f, "Document Viewer"),
            Self::Image => write!(f, "Image Viewer"),
            Self::Media => write!(f, "Media Player"),
            Self::TextCode => write!(f, "Text/Code Viewer"),
            Self::Archive => write!(f, "Archive Explorer"),
            Self::Hex => write!(f, "Hex Viewer"),
        }
    }
}

/// Support status of a format within Magic Key.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SupportStatus {
    /// Fully supported with a dedicated native or pure viewer engine.
    Supported,
    /// Partially supported (e.g., browse entries or view metadata).
    Partial,
    /// Unsupported for rich rendering, falls back cleanly to Hex Viewer.
    Unsupported,
}

impl std::fmt::Display for SupportStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Supported => write!(f, "Supported"),
            Self::Partial => write!(f, "Partial"),
            Self::Unsupported => write!(f, "Unsupported (Hex Fallback)"),
        }
    }
}

/// Immutable definition of a recognized file format.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FormatDefinition {
    /// Unique identifier (e.g. "pdf", "png", "rust").
    pub id: String,
    /// Human-readable display name (e.g. "Portable Document Format").
    pub display_name: String,
    /// Canonical MIME type (e.g. "application/pdf").
    pub mime_type: String,
    /// Known file extensions without leading dot (e.g. ["pdf"]).
    pub extensions: Vec<String>,
    /// High-level file category.
    pub category: FileCategory,
    /// Recommended viewing engine.
    pub recommended_viewer: ViewerEngine,
    /// Current engine support status.
    pub support_status: SupportStatus,
    /// Optional technical description.
    pub description: String,
}

impl FormatDefinition {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: impl Into<String>,
        display_name: impl Into<String>,
        mime_type: impl Into<String>,
        extensions: Vec<&str>,
        category: FileCategory,
        recommended_viewer: ViewerEngine,
        support_status: SupportStatus,
        description: impl Into<String>,
    ) -> Self {
        Self {
            id: id.into(),
            display_name: display_name.into(),
            mime_type: mime_type.into(),
            extensions: extensions
                .into_iter()
                .map(|s| s.to_ascii_lowercase())
                .collect(),
            category,
            recommended_viewer,
            support_status,
            description: description.into(),
        }
    }
}
