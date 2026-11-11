//! Automated tests for Magic Key File Detection Engine.

use magickey_core::file_detection::{
    detect_bom, BomType, DetectionConfidence, DetectionMethod, FileDetector,
};
use magickey_core::format_registry::{FileCategory, ViewerEngine};

#[test]
fn test_magic_bytes_detection_standard_formats() {
    let detector = FileDetector::new();

    // 1. PDF
    let pdf_header = b"%PDF-1.7\r\n\x25\xE2\xE3\xCF\xD3\r\n";
    let res = detector.detect_buffer(pdf_header, None);
    assert_eq!(res.format_id, "pdf");
    assert_eq!(res.category, FileCategory::Document);
    assert_eq!(res.suggested_viewer, ViewerEngine::Document);
    assert_eq!(res.confidence, DetectionConfidence::High);
    assert_eq!(res.detection_method, DetectionMethod::MagicBytes);

    // 2. PNG
    let png_header = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    ];
    let res = detector.detect_buffer(&png_header, None);
    assert_eq!(res.format_id, "png");
    assert_eq!(res.category, FileCategory::Image);
    assert_eq!(res.suggested_viewer, ViewerEngine::Image);
    assert_eq!(res.confidence, DetectionConfidence::High);

    // 3. JPEG
    let jpeg_header = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46];
    let res = detector.detect_buffer(&jpeg_header, None);
    assert_eq!(res.format_id, "jpeg");
    assert_eq!(res.category, FileCategory::Image);

    // 4. GIF (GIF89a)
    let gif_header = b"GIF89a\x80\x00\x60\x00";
    let res = detector.detect_buffer(gif_header, None);
    assert_eq!(res.format_id, "gif");

    // 5. WebP (RIFF....WEBP)
    let webp_header = b"RIFF\x20\x00\x00\x00WEBPVP8 ";
    let res = detector.detect_buffer(webp_header, None);
    assert_eq!(res.format_id, "webp");
    assert_eq!(res.category, FileCategory::Image);

    // 6. BMP
    let bmp_header = b"BM\x36\x00\x0C\x00\x00\x00\x00\x00";
    let res = detector.detect_buffer(bmp_header, None);
    assert_eq!(res.format_id, "bmp");

    // 7. ZIP
    let zip_header = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00];
    let res = detector.detect_buffer(&zip_header, None);
    assert_eq!(res.format_id, "zip");
    assert_eq!(res.category, FileCategory::Archive);
    assert_eq!(res.suggested_viewer, ViewerEngine::Archive);

    // 8. GZIP
    let gz_header = [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00];
    let res = detector.detect_buffer(&gz_header, None);
    assert_eq!(res.format_id, "gzip");
    assert_eq!(res.category, FileCategory::Archive);

    // 9. MP3 (ID3v2)
    let mp3_id3 = [0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00];
    let res = detector.detect_buffer(&mp3_id3, None);
    assert_eq!(res.format_id, "mp3");
    assert_eq!(res.category, FileCategory::Media);
    assert_eq!(res.suggested_viewer, ViewerEngine::Media);

    // 10. WAV (RIFF....WAVE)
    let wav_header = b"RIFF\x24\x08\x00\x00WAVEfmt ";
    let res = detector.detect_buffer(wav_header, None);
    assert_eq!(res.format_id, "wav");
    assert_eq!(res.category, FileCategory::Media);

    // 11. MP4 (....ftyp)
    let mp4_header = [
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D,
    ];
    let res = detector.detect_buffer(&mp4_header, None);
    assert_eq!(res.format_id, "mp4");
    assert_eq!(res.category, FileCategory::Media);

    // 12. FLAC
    let flac_header = b"fLaC\x00\x00\x00\x22";
    let res = detector.detect_buffer(flac_header, None);
    assert_eq!(res.format_id, "flac");

    // 13. ELF Binary
    let elf_header = [0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00];
    let res = detector.detect_buffer(&elf_header, None);
    assert_eq!(res.format_id, "elf");
    assert_eq!(res.category, FileCategory::Binary);
    assert_eq!(res.suggested_viewer, ViewerEngine::Hex);

    // 14. Dalvik DEX
    let dex_header = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x39, 0x00];
    let res = detector.detect_buffer(&dex_header, None);
    assert_eq!(res.format_id, "dex");
    assert_eq!(res.category, FileCategory::Binary);
    assert_eq!(res.suggested_viewer, ViewerEngine::Hex);
}

#[test]
fn test_misleading_and_incorrect_extensions() {
    let detector = FileDetector::new();

    // A real PDF file deliberately renamed to .png
    let pdf_header = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>";
    let res = detector.detect_buffer(pdf_header, Some("png"));
    assert_eq!(
        res.format_id, "pdf",
        "Engine must detect actual PDF regardless of .png extension"
    );
    assert_eq!(res.category, FileCategory::Document);
    assert_eq!(res.suggested_viewer, ViewerEngine::Document);

    // A real PNG file deliberately renamed to .txt
    let png_header = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    let res = detector.detect_buffer(&png_header, Some("txt"));
    assert_eq!(
        res.format_id, "png",
        "Engine must detect actual PNG regardless of .txt extension"
    );
    assert_eq!(res.category, FileCategory::Image);

    // A corrupt / garbage binary file claiming to be a .pdf
    let fake_pdf_data = [0xAA, 0xBB, 0xCC, 0xDD, 0x00, 0x11, 0x22, 0x33];
    let res = detector.detect_buffer(&fake_pdf_data, Some("pdf"));
    assert_eq!(
        res.format_id, "unknown_binary",
        "Must not trust .pdf extension when magic bytes fail"
    );
    assert_eq!(res.suggested_viewer, ViewerEngine::Hex);
    assert_eq!(res.confidence, DetectionConfidence::Unknown);
}

#[test]
fn test_bom_detection() {
    // UTF-8 BOM
    let utf8_bom = [0xEF, 0xBB, 0xBF, b'H', b'e', b'l', b'l', b'o'];
    assert_eq!(detect_bom(&utf8_bom), Some(BomType::Utf8));

    // UTF-16 LE BOM
    let utf16_le_bom = [0xFF, 0xFE, b'H', 0x00, b'i', 0x00];
    assert_eq!(detect_bom(&utf16_le_bom), Some(BomType::Utf16Le));

    // UTF-16 BE BOM
    let utf16_be_bom = [0xFE, 0xFF, 0x00, b'H', 0x00, b'i'];
    assert_eq!(detect_bom(&utf16_be_bom), Some(BomType::Utf16Be));

    // UTF-32 LE BOM (must take precedence over UTF-16 LE)
    let utf32_le_bom = [0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00];
    assert_eq!(detect_bom(&utf32_le_bom), Some(BomType::Utf32Le));

    // UTF-32 BE BOM (must take precedence over UTF-16 BE)
    let utf32_be_bom = [0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41];
    assert_eq!(detect_bom(&utf32_be_bom), Some(BomType::Utf32Be));

    // Integrated BOM detector test
    let detector = FileDetector::new();
    let res = detector.detect_buffer(&utf8_bom, Some("txt"));
    assert_eq!(res.format_id, "text");
    assert_eq!(res.detection_method, DetectionMethod::Bom);
    assert_eq!(res.confidence, DetectionConfidence::High);
}

#[test]
fn test_text_content_and_subtypes() {
    let detector = FileDetector::new();

    // 1. JSON
    let json_data = br#"{"name": "MagicKey", "version": "0.1.0", "active": true}"#;
    let res = detector.detect_buffer(json_data, None);
    assert_eq!(res.format_id, "json");
    assert_eq!(res.category, FileCategory::TextCode);
    assert_eq!(res.suggested_viewer, ViewerEngine::TextCode);

    // 2. SVG (Vector image classified as Image category)
    let svg_data = br#"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="10"/></svg>"#;
    let res = detector.detect_buffer(svg_data, None);
    assert_eq!(res.format_id, "svg");
    assert_eq!(res.category, FileCategory::Image);
    assert_eq!(res.suggested_viewer, ViewerEngine::Image);

    // 3. HTML
    let html_data = b"<!DOCTYPE html>\n<html><head><title>Test</title></head></html>";
    let res = detector.detect_buffer(html_data, None);
    assert_eq!(res.format_id, "html");

    // 4. XML
    let xml_data = b"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root><item id=\"1\"/></root>";
    let res = detector.detect_buffer(xml_data, None);
    assert_eq!(res.format_id, "xml");

    // 5. Markdown
    let md_data = b"# Magic Key Project\n\nUniversal file opener blueprint.";
    let res = detector.detect_buffer(md_data, None);
    assert_eq!(res.format_id, "markdown");

    // 6. Shell script
    let sh_data = b"#!/bin/bash\necho 'Running verification'";
    let res = detector.detect_buffer(sh_data, None);
    assert_eq!(res.format_id, "shell");

    // 7. Rust source code (verified text with .rs extension)
    let rs_data = b"pub fn calculate(x: i32) -> i32 { x * 2 }";
    let res = detector.detect_buffer(rs_data, Some("rs"));
    assert_eq!(res.format_id, "rust");
    assert_eq!(res.category, FileCategory::TextCode);
    assert_eq!(res.confidence, DetectionConfidence::Medium);
}

#[test]
fn test_empty_and_truncated_files() {
    let detector = FileDetector::new();

    // 1. Empty buffer (0 bytes)
    let empty: [u8; 0] = [];
    let res = detector.detect_buffer(&empty, None);
    assert_eq!(res.format_id, "empty");
    assert_eq!(res.suggested_viewer, ViewerEngine::Hex);
    assert_eq!(res.confidence, DetectionConfidence::High);

    // 2. Truncated 1-byte file
    let single_byte = [0x50]; // First byte of ZIP (PK)
    let res = detector.detect_buffer(&single_byte, None);
    // Not enough bytes to confirm ZIP -> safe fallback
    assert_eq!(res.suggested_viewer, ViewerEngine::TextCode); // single ASCII 'P' is valid text!

    // 3. Truncated binary byte (null)
    let single_null = [0x00];
    let res = detector.detect_buffer(&single_null, None);
    assert_eq!(res.format_id, "unknown_binary");
    assert_eq!(res.suggested_viewer, ViewerEngine::Hex);

    // 4. Truncated PDF header (only 3 bytes: "%PD")
    let trunc_pdf = b"%PD";
    let res = detector.detect_buffer(trunc_pdf, None);
    // Incomplete magic -> treated as text
    assert_eq!(res.format_id, "text");
}
