//! Magic byte signature definitions and matching logic.

use serde::{Deserialize, Serialize};

/// A secondary pattern check at an additional offset (e.g. 'WEBP' at offset 8 in RIFF).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SecondaryPattern {
    pub offset: usize,
    pub bytes: String,
    #[serde(default)]
    pub mask: Option<String>,
}

/// A primary magic byte pattern rule.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MagicPattern {
    pub offset: usize,
    pub bytes: String,
    #[serde(default)]
    pub mask: Option<String>,
    #[serde(default)]
    pub secondary: Option<SecondaryPattern>,
}

/// A format signature definition loaded from the database.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignatureEntry {
    pub id: String,
    pub name: String,
    pub category: String,
    pub mime: String,
    pub extensions: Vec<String>,
    #[serde(default)]
    pub engine: Option<String>,
    pub magic: Vec<MagicPattern>,
}

/// The compiled signature database.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignatureDb {
    pub version: String,
    pub signatures: Vec<SignatureEntry>,
}

impl SignatureDb {
    /// Loads the embedded signature database compiled into the binary.
    pub fn load_embedded() -> Result<Self, String> {
        let json_str = include_str!("../../../file_detection/signatures.json");
        serde_json::from_str(json_str)
            .map_err(|e| format!("Failed to parse embedded signatures.json: {}", e))
    }

    /// Loads a signature database from an external JSON string.
    pub fn from_json(json_str: &str) -> Result<Self, String> {
        serde_json::from_str(json_str)
            .map_err(|e| format!("Failed to parse signatures JSON: {}", e))
    }
}

/// Helper to decode a hex string into raw bytes.
pub fn hex_to_bytes(hex: &str) -> Option<Vec<u8>> {
    let clean: String = hex.chars().filter(|c| !c.is_whitespace()).collect();
    if !clean.len().is_multiple_of(2) {
        return None;
    }
    (0..clean.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&clean[i..i + 2], 16).ok())
        .collect()
}

/// Matches a single magic pattern against a raw byte buffer.
pub fn match_pattern(pattern: &MagicPattern, buffer: &[u8]) -> bool {
    let expected = match hex_to_bytes(&pattern.bytes) {
        Some(b) => b,
        None => return false,
    };

    let mask = pattern.mask.as_deref().and_then(hex_to_bytes);

    if !match_slice(buffer, pattern.offset, &expected, mask.as_deref()) {
        return false;
    }

    // Check secondary pattern if defined
    if let Some(sec) = &pattern.secondary {
        let sec_expected = match hex_to_bytes(&sec.bytes) {
            Some(b) => b,
            None => return false,
        };
        let sec_mask = sec.mask.as_deref().and_then(hex_to_bytes);
        if !match_slice(buffer, sec.offset, &sec_expected, sec_mask.as_deref()) {
            return false;
        }
    }

    true
}

fn match_slice(buffer: &[u8], offset: usize, expected: &[u8], mask: Option<&[u8]>) -> bool {
    if buffer.len() < offset + expected.len() {
        return false;
    }

    let actual = &buffer[offset..offset + expected.len()];

    if let Some(m) = mask {
        if m.len() != expected.len() {
            return false;
        }
        for i in 0..expected.len() {
            if (actual[i] & m[i]) != (expected[i] & m[i]) {
                return false;
            }
        }
        true
    } else {
        actual == expected
    }
}
