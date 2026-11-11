//! Safe, bounded text content inspection and sub-type identification.

/// Text sub-type classification determined from content tokens.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextSubType {
    PlainText,
    Json,
    Xml,
    Html,
    Svg,
    Markdown,
    ShellScript,
}

/// Analysis result for a bounded buffer.
#[derive(Debug, Clone, PartialEq)]
pub struct TextAnalysis {
    pub is_text: bool,
    pub sub_type: TextSubType,
    pub null_byte_count: usize,
    pub control_char_count: usize,
    pub valid_utf8: bool,
}

/// Bounded inspection of buffer to distinguish text from binary and identify structured text.
pub fn analyze_text_content(buffer: &[u8]) -> TextAnalysis {
    if buffer.is_empty() {
        return TextAnalysis {
            is_text: true,
            sub_type: TextSubType::PlainText,
            null_byte_count: 0,
            control_char_count: 0,
            valid_utf8: true,
        };
    }

    let inspect_len = buffer.len().min(512);
    let sample = &buffer[..inspect_len];

    let mut null_bytes = 0;
    let mut control_chars = 0;

    for &b in sample {
        if b == 0 {
            null_bytes += 1;
        } else if b < 32 && b != b'\t' && b != b'\n' && b != b'\r' {
            control_chars += 1;
        }
    }

    // Binary criteria: any null bytes in sample or > 2% control characters
    if null_bytes > 0 || (control_chars * 100 / inspect_len) > 2 {
        return TextAnalysis {
            is_text: false,
            sub_type: TextSubType::PlainText,
            null_byte_count: null_bytes,
            control_char_count: control_chars,
            valid_utf8: false,
        };
    }

    // Check UTF-8 validity
    let (valid_utf8, text_str) = match std::str::from_utf8(sample) {
        Ok(s) => (true, s),
        Err(e) => {
            // Check if valid up to an incomplete final UTF-8 character at boundary
            let valid_up_to = e.valid_up_to();
            if valid_up_to > 0 && e.error_len().is_none() {
                // Incomplete multi-byte sequence at sample boundary
                let s = std::str::from_utf8(&sample[..valid_up_to]).unwrap_or_default();
                (true, s)
            } else {
                (false, "")
            }
        }
    };

    if !valid_utf8 {
        return TextAnalysis {
            is_text: false,
            sub_type: TextSubType::PlainText,
            null_byte_count: null_bytes,
            control_char_count: control_chars,
            valid_utf8: false,
        };
    }

    let sub_type = detect_text_sub_type(text_str);

    TextAnalysis {
        is_text: true,
        sub_type,
        null_byte_count: null_bytes,
        control_char_count: control_chars,
        valid_utf8: true,
    }
}

fn detect_text_sub_type(text: &str) -> TextSubType {
    let trimmed = text.trim_start();

    if trimmed.starts_with("#!/") || trimmed.starts_with("#! /") {
        return TextSubType::ShellScript;
    }

    if trimmed.starts_with('{') || trimmed.starts_with('[') {
        return TextSubType::Json;
    }

    if trimmed.starts_with("<?xml") {
        if text.contains("<svg") {
            return TextSubType::Svg;
        }
        return TextSubType::Xml;
    }

    if trimmed.starts_with("<svg") {
        return TextSubType::Svg;
    }

    let lower = trimmed.to_ascii_lowercase();
    if lower.starts_with("<!doctype html") || lower.starts_with("<html") {
        return TextSubType::Html;
    }

    if trimmed.starts_with("# ") || trimmed.starts_with("## ") || trimmed.starts_with("---\n") {
        return TextSubType::Markdown;
    }

    TextSubType::PlainText
}
