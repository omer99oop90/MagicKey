//! Automated tests for Format Registry and Engine Routing.

use magickey_core::format_registry::{FileCategory, FormatRegistry, SupportStatus, ViewerEngine};

#[test]
fn test_registry_lookups() {
    let registry = FormatRegistry::default();

    // 1. By ID
    let pdf = registry.get_by_id("pdf").expect("PDF must be registered");
    assert_eq!(pdf.display_name, "Portable Document Format");
    assert_eq!(pdf.category, FileCategory::Document);
    assert_eq!(pdf.recommended_viewer, ViewerEngine::Document);
    assert_eq!(pdf.support_status, SupportStatus::Supported);

    // 2. By Extension (case-insensitive and with/without dot)
    let png1 = registry.get_by_extension("png").expect("png must be found");
    let png2 = registry
        .get_by_extension(".PNG")
        .expect(".PNG must be found");
    assert_eq!(png1.id, png2.id);
    assert_eq!(png1.id, "png");
    assert_eq!(png1.recommended_viewer, ViewerEngine::Image);

    // 3. By MIME type
    let mp3 = registry
        .get_by_mime("audio/mpeg")
        .expect("MP3 MIME must be found");
    assert_eq!(mp3.id, "mp3");
    assert_eq!(mp3.recommended_viewer, ViewerEngine::Media);

    // 4. Source code extension
    let rust = registry
        .get_by_extension("rs")
        .expect("Rust source must be found");
    assert_eq!(rust.id, "rust");
    assert_eq!(rust.category, FileCategory::TextCode);
    assert_eq!(rust.recommended_viewer, ViewerEngine::TextCode);
}

#[test]
fn test_registry_routing_and_fallbacks() {
    let registry = FormatRegistry::default();

    // Known formats resolve to their designated viewer engine
    assert_eq!(registry.resolve_viewer("pdf"), ViewerEngine::Document);
    assert_eq!(registry.resolve_viewer("png"), ViewerEngine::Image);
    assert_eq!(registry.resolve_viewer("mp4"), ViewerEngine::Media);
    assert_eq!(registry.resolve_viewer("zip"), ViewerEngine::Archive);
    assert_eq!(registry.resolve_viewer("rust"), ViewerEngine::TextCode);
    assert_eq!(registry.resolve_viewer("elf"), ViewerEngine::Hex);
    assert_eq!(registry.resolve_viewer("dex"), ViewerEngine::Hex);

    // Unregistered / unknown formats fallback to Hex Viewer
    assert_eq!(registry.resolve_viewer("unknown_xyz"), ViewerEngine::Hex);
    assert_eq!(
        registry.resolve_viewer("corrupted_stream"),
        ViewerEngine::Hex
    );
}

#[test]
fn test_registry_data_integrity() {
    let registry = FormatRegistry::default();
    let all = registry.list_all();

    assert!(
        all.len() >= 25,
        "Registry should contain at least 25 standard formats"
    );

    for def in all {
        assert!(!def.id.is_empty(), "Format ID must not be empty");
        assert!(
            !def.display_name.is_empty(),
            "Display name must not be empty"
        );
        assert!(!def.mime_type.is_empty(), "MIME type must not be empty");
        assert!(
            def.mime_type.contains('/'),
            "MIME type must contain a slash: {}",
            def.mime_type
        );
        assert!(
            !def.extensions.is_empty(),
            "Extensions list must not be empty for {}",
            def.id
        );
    }
}
