//! Canonical 16-byte Hex Row Formatter.

use serde::{Deserialize, Serialize};

/// A single formatted 16-byte row in the Hex viewer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HexRow {
    /// Absolute byte offset in the file.
    pub offset: u64,
    /// Number of bytes in this row (1 to 16).
    pub byte_count: usize,
    /// Hexadecimal string representation with 8-byte spacing.
    pub hex_dump: String,
    /// Printable ASCII representation with non-printable bytes replaced by '.'.
    pub ascii_dump: String,
    /// The complete aligned line: "OFFSET  HEX_BYTES  |ASCII|".
    pub formatted_line: String,
}

/// Formats up to 16 bytes into a canonical Hex row.
pub fn format_row(offset: u64, bytes: &[u8]) -> HexRow {
    let byte_count = bytes.len().min(16);
    let slice = &bytes[..byte_count];

    // Format 16 bytes: two groups of 8 separated by two spaces
    let mut hex_parts = Vec::with_capacity(16);
    for i in 0..16 {
        if let Some(&b) = slice.get(i) {
            hex_parts.push(format!("{:02X}", b));
        } else {
            hex_parts.push("  ".to_string());
        }
    }

    let left_group = hex_parts[0..8].join(" ");
    let right_group = hex_parts[8..16].join(" ");
    let hex_dump = format!("{}  {}", left_group, right_group);

    // Format ASCII representation
    let mut ascii_chars = String::with_capacity(byte_count);
    for &b in slice {
        if (32..=126).contains(&b) {
            ascii_chars.push(b as char);
        } else {
            ascii_chars.push('.');
        }
    }
    let ascii_dump = format!("|{}|", ascii_chars);

    // Complete line: Offset (8 hex digits)  Hex Dump  |ASCII|
    let formatted_line = format!("{:08X}  {}  {}", offset, hex_dump, ascii_dump);

    HexRow {
        offset,
        byte_count,
        hex_dump,
        ascii_dump,
        formatted_line,
    }
}
