//! Byte Order Mark (BOM) detection for text encodings.

use serde::{Deserialize, Serialize};

/// Recognized Byte Order Mark types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BomType {
    Utf8,
    Utf16Le,
    Utf16Be,
    Utf32Le,
    Utf32Be,
}

impl BomType {
    /// Returns the length of the BOM in bytes.
    pub fn length(&self) -> usize {
        match self {
            Self::Utf8 => 3,
            Self::Utf16Le | Self::Utf16Be => 2,
            Self::Utf32Le | Self::Utf32Be => 4,
        }
    }

    /// Returns human-readable encoding label.
    pub fn encoding_label(&self) -> &'static str {
        match self {
            Self::Utf8 => "UTF-8 (with BOM)",
            Self::Utf16Le => "UTF-16 Little Endian",
            Self::Utf16Be => "UTF-16 Big Endian",
            Self::Utf32Le => "UTF-32 Little Endian",
            Self::Utf32Be => "UTF-32 Big Endian",
        }
    }
}

/// Detects if a byte slice begins with a known Unicode Byte Order Mark (BOM).
pub fn detect_bom(buffer: &[u8]) -> Option<BomType> {
    if buffer.len() >= 4 {
        // UTF-32 LE: FF FE 00 00 (Check before UTF-16 LE)
        if buffer[0..4] == [0xFF, 0xFE, 0x00, 0x00] {
            return Some(BomType::Utf32Le);
        }
        // UTF-32 BE: 00 00 FE FF (Check before UTF-16 BE)
        if buffer[0..4] == [0x00, 0x00, 0xFE, 0xFF] {
            return Some(BomType::Utf32Be);
        }
    }

    if buffer.len() >= 3 {
        // UTF-8: EF BB BF
        if buffer[0..3] == [0xEF, 0xBB, 0xBF] {
            return Some(BomType::Utf8);
        }
    }

    if buffer.len() >= 2 {
        // UTF-16 LE: FF FE
        if buffer[0..2] == [0xFF, 0xFE] {
            return Some(BomType::Utf16Le);
        }
        // UTF-16 BE: FE FF
        if buffer[0..2] == [0xFE, 0xFF] {
            return Some(BomType::Utf16Be);
        }
    }

    None
}
