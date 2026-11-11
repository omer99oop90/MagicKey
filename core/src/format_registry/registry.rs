//! Centralized Format Registry implementation.

use super::model::{FileCategory, FormatDefinition, SupportStatus, ViewerEngine};
use std::collections::HashMap;

/// Central registry holding all recognized file format specifications.
#[derive(Debug, Clone)]
pub struct FormatRegistry {
    formats: HashMap<String, FormatDefinition>,
    ext_index: HashMap<String, String>,
    mime_index: HashMap<String, String>,
}

impl Default for FormatRegistry {
    fn default() -> Self {
        let mut registry = Self::new();
        registry.register_defaults();
        registry
    }
}

impl FormatRegistry {
    /// Creates an empty format registry.
    pub fn new() -> Self {
        Self {
            formats: HashMap::new(),
            ext_index: HashMap::new(),
            mime_index: HashMap::new(),
        }
    }

    /// Registers a format definition and indexes its extensions and MIME type.
    pub fn register(&mut self, def: FormatDefinition) {
        let id = def.id.clone();
        for ext in &def.extensions {
            self.ext_index.insert(ext.to_ascii_lowercase(), id.clone());
        }
        self.mime_index
            .insert(def.mime_type.to_ascii_lowercase(), id.clone());
        self.formats.insert(id, def);
    }

    /// Retrieves a format definition by unique format ID.
    pub fn get_by_id(&self, id: &str) -> Option<&FormatDefinition> {
        self.formats.get(id)
    }

    /// Retrieves a format definition by file extension (without dot).
    pub fn get_by_extension(&self, ext: &str) -> Option<&FormatDefinition> {
        let ext_lower = ext.trim_start_matches('.').to_ascii_lowercase();
        self.ext_index
            .get(&ext_lower)
            .and_then(|id| self.formats.get(id))
    }

    /// Retrieves a format definition by MIME type.
    pub fn get_by_mime(&self, mime: &str) -> Option<&FormatDefinition> {
        let mime_lower = mime.to_ascii_lowercase();
        self.mime_index
            .get(&mime_lower)
            .and_then(|id| self.formats.get(id))
    }

    /// Returns a list of all registered format definitions.
    pub fn list_all(&self) -> Vec<&FormatDefinition> {
        let mut list: Vec<&FormatDefinition> = self.formats.values().collect();
        list.sort_by(|a, b| a.id.cmp(&b.id));
        list
    }

    /// Returns the total count of registered formats.
    pub fn count(&self) -> usize {
        self.formats.len()
    }

    /// Resolves the recommended viewer engine for a format ID.
    pub fn resolve_viewer(&self, format_id: &str) -> ViewerEngine {
        self.formats
            .get(format_id)
            .map(|f| f.recommended_viewer)
            .unwrap_or(ViewerEngine::Hex)
    }

    /// Populates standard formats for Magic Key Phase 1.
    pub fn register_defaults(&mut self) {
        // Document Formats
        self.register(FormatDefinition::new(
            "pdf",
            "Portable Document Format",
            "application/pdf",
            vec!["pdf"],
            FileCategory::Document,
            ViewerEngine::Document,
            SupportStatus::Supported,
            "Standard vector and raster fixed-layout document format.",
        ));

        // Image Formats
        self.register(FormatDefinition::new(
            "png",
            "Portable Network Graphics",
            "image/png",
            vec!["png"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "Lossless bitmap image format with alpha channel transparency.",
        ));
        self.register(FormatDefinition::new(
            "jpeg",
            "JPEG Image",
            "image/jpeg",
            vec!["jpg", "jpeg", "jpe"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "Standard lossy photographic image format.",
        ));
        self.register(FormatDefinition::new(
            "gif",
            "Graphics Interchange Format",
            "image/gif",
            vec!["gif"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "Paletted image and short animation format.",
        ));
        self.register(FormatDefinition::new(
            "webp",
            "WebP Image",
            "image/webp",
            vec!["webp"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "Modern lossy and lossless raster web image format.",
        ));
        self.register(FormatDefinition::new(
            "bmp",
            "Bitmap Image",
            "image/bmp",
            vec!["bmp"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "Uncompressed raster device-independent bitmap image format.",
        ));
        self.register(FormatDefinition::new(
            "avif",
            "AV1 Image File Format",
            "image/avif",
            vec!["avif"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "Next-generation image compression format based on AV1 video codec.",
        ));
        self.register(FormatDefinition::new(
            "svg",
            "Scalable Vector Graphics",
            "image/svg+xml",
            vec!["svg"],
            FileCategory::Image,
            ViewerEngine::Image,
            SupportStatus::Supported,
            "XML-based 2D vector graphic format.",
        ));

        // Media Formats (Audio & Video)
        self.register(FormatDefinition::new(
            "mp4",
            "MPEG-4 Video",
            "video/mp4",
            vec!["mp4", "m4v"],
            FileCategory::Media,
            ViewerEngine::Media,
            SupportStatus::Supported,
            "Standard digital multimedia container for H.264/HEVC/AV1 and AAC.",
        ));
        self.register(FormatDefinition::new(
            "mkv",
            "Matroska / WebM Video",
            "video/x-matroska",
            vec!["mkv", "webm"],
            FileCategory::Media,
            ViewerEngine::Media,
            SupportStatus::Supported,
            "Extensible open standard multimedia container.",
        ));
        self.register(FormatDefinition::new(
            "mp3",
            "MPEG Audio Layer III",
            "audio/mpeg",
            vec!["mp3"],
            FileCategory::Media,
            ViewerEngine::Media,
            SupportStatus::Supported,
            "Universal lossy audio compression format.",
        ));
        self.register(FormatDefinition::new(
            "wav",
            "Waveform Audio File",
            "audio/wav",
            vec!["wav"],
            FileCategory::Media,
            ViewerEngine::Media,
            SupportStatus::Supported,
            "Uncompressed PCM linear audio container format.",
        ));
        self.register(FormatDefinition::new(
            "flac",
            "Free Lossless Audio Codec",
            "audio/flac",
            vec!["flac"],
            FileCategory::Media,
            ViewerEngine::Media,
            SupportStatus::Supported,
            "Open bit-exact lossless audio compression format.",
        ));
        self.register(FormatDefinition::new(
            "ogg",
            "Ogg Vorbis / Opus Media",
            "audio/ogg",
            vec!["ogg", "oga", "ogv"],
            FileCategory::Media,
            ViewerEngine::Media,
            SupportStatus::Supported,
            "Xiph.Org open multimedia container for Vorbis, Opus, and Theora.",
        ));

        // Archive Formats
        self.register(FormatDefinition::new(
            "zip",
            "ZIP Archive",
            "application/zip",
            vec!["zip"],
            FileCategory::Archive,
            ViewerEngine::Archive,
            SupportStatus::Supported,
            "Ubiquitous lossless compressed archive format.",
        ));
        self.register(FormatDefinition::new(
            "gzip",
            "Gzip Compressed Stream",
            "application/gzip",
            vec!["gz", "tgz"],
            FileCategory::Archive,
            ViewerEngine::Archive,
            SupportStatus::Supported,
            "Single-stream Deflate compressed archive format.",
        ));
        self.register(FormatDefinition::new(
            "tar",
            "Tarball Archive",
            "application/x-tar",
            vec!["tar"],
            FileCategory::Archive,
            ViewerEngine::Archive,
            SupportStatus::Supported,
            "Tape archive container preserving file attributes.",
        ));
        self.register(FormatDefinition::new(
            "7z",
            "7-Zip Archive",
            "application/x-7z-compressed",
            vec!["7z"],
            FileCategory::Archive,
            ViewerEngine::Archive,
            SupportStatus::Partial,
            "High-compression ratio archive utilizing LZMA/LZMA2.",
        ));
        self.register(FormatDefinition::new(
            "bzip2",
            "Bzip2 Compressed Stream",
            "application/x-bzip2",
            vec!["bz2"],
            FileCategory::Archive,
            ViewerEngine::Archive,
            SupportStatus::Supported,
            "Burrows-Wheeler block-sorting compressed archive stream.",
        ));

        // Text & Code Formats
        self.register(FormatDefinition::new(
            "text",
            "Plain Text",
            "text/plain",
            vec!["txt", "text", "log"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Unformatted plain human-readable text document.",
        ));
        self.register(FormatDefinition::new(
            "markdown",
            "Markdown Document",
            "text/markdown",
            vec!["md", "markdown"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Lightweight plain text markup language with formatting tokens.",
        ));
        self.register(FormatDefinition::new(
            "json",
            "JavaScript Object Notation",
            "application/json",
            vec!["json"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Lightweight structured data interchange format.",
        ));
        self.register(FormatDefinition::new(
            "yaml",
            "YAML Data",
            "application/yaml",
            vec!["yaml", "yml"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Human-friendly data serialization standard.",
        ));
        self.register(FormatDefinition::new(
            "xml",
            "Extensible Markup Language",
            "application/xml",
            vec!["xml"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Structured hierarchical tag-based markup format.",
        ));
        self.register(FormatDefinition::new(
            "html",
            "HyperText Markup Language",
            "text/html",
            vec!["html", "htm"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Standard document structure for Web viewports.",
        ));
        self.register(FormatDefinition::new(
            "rust",
            "Rust Source Code",
            "text/x-rust",
            vec!["rs"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Memory-safe systems programming language source file.",
        ));
        self.register(FormatDefinition::new(
            "python",
            "Python Source Code",
            "text/x-python",
            vec!["py", "pyw"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Interpreted, dynamic high-level programming language script.",
        ));
        self.register(FormatDefinition::new(
            "c_cpp",
            "C / C++ Source Code",
            "text/x-c",
            vec!["c", "cpp", "cc", "cxx", "h", "hpp"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Standard compiled systems language source and header file.",
        ));
        self.register(FormatDefinition::new(
            "java",
            "Java Source Code",
            "text/x-java-source",
            vec!["java"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Object-oriented class-based programming language source file.",
        ));
        self.register(FormatDefinition::new(
            "dart",
            "Dart Source Code",
            "text/x-dart",
            vec!["dart"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Client-optimized programming language source file for Flutter.",
        ));
        self.register(FormatDefinition::new(
            "javascript",
            "JavaScript / TypeScript",
            "text/javascript",
            vec!["js", "mjs", "cjs", "ts"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Dynamic ECMAScript web language source file.",
        ));
        self.register(FormatDefinition::new(
            "shell",
            "Shell Script",
            "text/x-shellscript",
            vec!["sh", "bash", "zsh"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Unix command-line shell script file.",
        ));
        self.register(FormatDefinition::new(
            "sql",
            "Structured Query Language",
            "application/sql",
            vec!["sql"],
            FileCategory::TextCode,
            ViewerEngine::TextCode,
            SupportStatus::Supported,
            "Relational database query and schema definition script.",
        ));

        // Binary & Executable Formats (Hex Fallback)
        self.register(FormatDefinition::new(
            "sqlite",
            "SQLite 3 Database",
            "application/vnd.sqlite3",
            vec!["sqlite", "db", "sqlite3"],
            FileCategory::Binary,
            ViewerEngine::Hex,
            SupportStatus::Partial,
            "Self-contained, serverless zero-configuration relational database file.",
        ));
        self.register(FormatDefinition::new(
            "elf",
            "Executable and Linkable Format",
            "application/x-executable",
            vec!["so", "bin", "elf"],
            FileCategory::Binary,
            ViewerEngine::Hex,
            SupportStatus::Unsupported,
            "Standard binary format for compiled Linux and Android native code.",
        ));
        self.register(FormatDefinition::new(
            "dex",
            "Dalvik Executable",
            "application/vnd.android.dex",
            vec!["dex"],
            FileCategory::Binary,
            ViewerEngine::Hex,
            SupportStatus::Unsupported,
            "Compiled Dalvik bytecode format executing on Android runtime.",
        ));
        self.register(FormatDefinition::new(
            "class",
            "Java Bytecode Class",
            "application/java-vm",
            vec!["class"],
            FileCategory::Binary,
            ViewerEngine::Hex,
            SupportStatus::Unsupported,
            "Compiled Java virtual machine bytecode file.",
        ));
        self.register(FormatDefinition::new(
            "pe_exe",
            "Windows Portable Executable",
            "application/vnd.microsoft.portable-executable",
            vec!["exe", "dll", "sys"],
            FileCategory::Binary,
            ViewerEngine::Hex,
            SupportStatus::Unsupported,
            "Compiled executable binary for Microsoft Windows.",
        ));

        // Generic Fallback
        self.register(FormatDefinition::new(
            "unknown_binary",
            "Unknown Binary Stream",
            "application/octet-stream",
            vec!["bin"],
            FileCategory::Binary,
            ViewerEngine::Hex,
            SupportStatus::Unsupported,
            "Raw unclassified binary data stream displayed via virtualized Hex engine.",
        ));
    }
}
