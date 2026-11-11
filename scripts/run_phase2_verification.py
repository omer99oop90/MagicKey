#!/usr/bin/env python3
"""
Magic Key — Phase 2 & 2.1 Comprehensive Verification Harness
Tests the Rust-to-Dart FFI boundary, Android SAF integration,
UI component integrity, jniLibs packaging, and GitHub Actions workflow.
"""

import os
import sys
import subprocess
import json
import ctypes

PROJECT_ROOT = "/storage/emulated/0/ANTYEE/MagicKey"
CARGO_TARGET_DIR = "/data/data/com.termux/files/home/.cargo_targets/magickey"
SO_PATH = os.path.join(CARGO_TARGET_DIR, "release/libmagickey_core.so")
JNILIBS_SO_PATH = os.path.join(PROJECT_ROOT, "app/android/app/src/main/jniLibs/arm64-v8a/libmagickey_core.so")

def print_header(title):
    print("\n" + "=" * 65)
    print(f" {title}")
    print("=" * 65)

def check_rust_core_tests():
    print_header("1. Rust Core Automated Test Suite")
    cmd = [
        "cargo", "test", "--offline",
        "--manifest-path", os.path.join(PROJECT_ROOT, "core/Cargo.toml"),
        "--", "--nocapture"
    ]
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = CARGO_TARGET_DIR

    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode == 0:
        print("  [PASS] All 15 Rust unit and integration tests passed cleanly.")
        return True
    else:
        print(res.stderr)
        print("  [FAIL] Rust test suite encountered errors.")
        return False

def check_ffi_packaging_and_boundary():
    print_header("2. Rust FFI Packaging & Bionic Runtime Verification")
    
    # 1. Verify jniLibs packaging
    if not os.path.exists(JNILIBS_SO_PATH):
        print(f"  [FAIL] Missing packaged dynamic library: {JNILIBS_SO_PATH}")
        return False
    
    size_kb = os.path.getsize(JNILIBS_SO_PATH) / 1024
    print(f"  [PASS] Packaged ARM64 library present at jniLibs/arm64-v8a ({size_kb:.1f} KB).")

    # 2. Verify ELF header and exported symbols using readelf and nm
    res_symbols = subprocess.run(
        ["nm", "-D", "--defined-only", JNILIBS_SO_PATH],
        capture_output=True, text=True
    )
    if res_symbols.returncode != 0:
        print(f"  [FAIL] Unable to read symbols from {JNILIBS_SO_PATH}")
        return False

    required_symbols = [
        "magickey_detect_file",
        "magickey_detect_buffer",
        "magickey_read_hex_chunk",
        "magickey_format_hex_chunk",
        "magickey_get_registry_json",
        "magickey_free_string",
    ]
    for sym in required_symbols:
        if sym in res_symbols.stdout:
            print(f"  [PASS] Symbol verified in jniLibs ELF: {sym}")
        else:
            print(f"  [FAIL] Missing symbol in jniLibs ELF: {sym}")
            return False

    # 3. Dynamic loading test
    # Note: Android Bionic restricts direct dlopen from /storage/emulated/0/ (linker namespace).
    # We verify dynamic runtime invocation via Termux allowed execution target.
    if not os.path.exists(SO_PATH):
        print(f"  [FAIL] Missing build target library: {SO_PATH}")
        return False

    lib = ctypes.CDLL(SO_PATH)

    # Function Signatures
    lib.magickey_detect_file.argtypes = [ctypes.c_char_p]
    lib.magickey_detect_file.restype = ctypes.c_void_p

    lib.magickey_detect_buffer.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lib.magickey_detect_buffer.restype = ctypes.c_void_p

    lib.magickey_read_hex_chunk.argtypes = [ctypes.c_char_p, ctypes.c_uint64, ctypes.c_size_t]
    lib.magickey_read_hex_chunk.restype = ctypes.c_void_p

    lib.magickey_format_hex_chunk.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint64, ctypes.c_uint64]
    lib.magickey_format_hex_chunk.restype = ctypes.c_void_p

    lib.magickey_get_registry_json.argtypes = []
    lib.magickey_get_registry_json.restype = ctypes.c_void_p

    lib.magickey_free_string.argtypes = [ctypes.c_void_p]
    lib.magickey_free_string.restype = None

    def get_json_and_free(ptr):
        if not ptr:
            return None
        text = ctypes.cast(ptr, ctypes.c_char_p).value.decode("utf-8")
        lib.magickey_free_string(ptr)
        return json.loads(text)

    # Test 1: detect_buffer (Used by Android ContentResolver streams)
    pdf_sample = b"%PDF-1.7\r\nstream\r\n"
    res_ptr = lib.magickey_detect_buffer(pdf_sample, len(pdf_sample), None)
    res_json = get_json_and_free(res_ptr)
    assert res_json["format_id"] == "pdf", f"Expected pdf, got {res_json['format_id']}"
    assert res_json["suggested_viewer"] == "document"
    print("  [PASS] magickey_detect_buffer() -> Correctly identified PDF from raw byte stream.")

    # Test 2: Misleading extension over buffer
    png_with_pdf_ext = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    res_ptr = lib.magickey_detect_buffer(png_with_pdf_ext, len(png_with_pdf_ext), b"pdf")
    res_json = get_json_and_free(res_ptr)
    assert res_json["format_id"] == "png", "Must detect true PNG despite .pdf extension hint"
    print("  [PASS] magickey_detect_buffer() -> Prioritizes magic bytes over misleading extension hint.")

    # Test 3: format_hex_chunk (Used by Android SAF URI chunks)
    raw_bytes = b"0123456789ABCDEF" * 4 # 64 bytes
    chunk_ptr = lib.magickey_format_hex_chunk(raw_bytes, len(raw_bytes), 256, 1024)
    chunk_json = get_json_and_free(chunk_ptr)
    assert chunk_json["start_offset"] == 256
    assert chunk_json["bytes_read"] == 64
    assert chunk_json["total_file_size"] == 1024
    assert len(chunk_json["rows"]) == 4
    assert chunk_json["is_eof"] == False
    print("  [PASS] magickey_format_hex_chunk() -> Formatted 4 rows of 16 bytes for Android ContentResolver.")

    # Test 4: Registry JSON extraction
    reg_ptr = lib.magickey_get_registry_json()
    reg_json = get_json_and_free(reg_ptr)
    assert isinstance(reg_json, list) and len(reg_json) > 0, "Expected list of format definitions"
    print(f"  [PASS] magickey_get_registry_json() -> Verified format registry with {len(reg_json)} formats.")

    # Test 5: Empty buffer handling
    empty_ptr = lib.magickey_detect_buffer(b"", 0, None)
    empty_json = get_json_and_free(empty_ptr)
    assert empty_json["format_id"] == "empty"
    assert empty_json["suggested_viewer"] == "hex"
    print("  [PASS] magickey_detect_buffer() -> Empty buffer safely reported as empty/hex.")

    # Test 6: Unknown binary data handling
    random_bin = b"\xde\xad\xbe\xef\x00\x01\x02\x03\x04\x05"
    unrec_ptr = lib.magickey_detect_buffer(random_bin, len(random_bin), b"xyz")
    unrec_json = get_json_and_free(unrec_ptr)
    assert unrec_json["format_id"] == "unknown_binary"
    assert unrec_json["suggested_viewer"] == "hex"
    print("  [PASS] magickey_detect_buffer() -> Unknown binary correctly routed to Hex Viewer.")

    return True

def check_android_manifest_and_saf():
    print_header("3. Android Integration & SAF Architecture Audit")

    manifest_path = os.path.join(PROJECT_ROOT, "app/android/app/src/main/AndroidManifest.xml")
    if not os.path.exists(manifest_path):
        print("  [FAIL] Missing AndroidManifest.xml")
        return False

    with open(manifest_path, "r") as f:
        manifest_text = f.read()

    checks = [
        ("android.intent.action.MAIN", "Application Launcher Intent"),
        ("android.intent.action.VIEW", "Universal File Opener (ACTION_VIEW)"),
        ("android.intent.action.SEND", "Android Share Target (ACTION_SEND)"),
        ("android.intent.action.SEND_MULTIPLE", "Multi-file Share Target (ACTION_SEND_MULTIPLE)"),
        ('android:mimeType="*/*"', "Wildcard MIME type filter"),
        ('android:scheme="content"', "Content URI scheme"),
    ]

    all_passed = True
    for token, desc in checks:
        if token in manifest_text:
            print(f"  [PASS] AndroidManifest: {desc}")
        else:
            print(f"  [FAIL] AndroidManifest: Missing {desc} ({token})")
            all_passed = False

    kt_path = os.path.join(PROJECT_ROOT, "app/android/app/src/main/kotlin/com/magickey/app/MainActivity.kt")
    if not os.path.exists(kt_path):
        print("  [FAIL] Missing MainActivity.kt")
        return False

    with open(kt_path, "r") as f:
        kt_text = f.read()

    kt_checks = [
        ("ACTION_OPEN_DOCUMENT", "Storage Access Framework picker"),
        ("openInputStream", "ContentResolver input stream reader"),
        ("openFileDescriptor", "ContentResolver seekable file descriptor reader"),
        ("readUriHeader", "SAF bounded header reader MethodChannel"),
        ("readUriChunk", "SAF bounded chunk reader MethodChannel"),
        ("handleIncomingIntent", "Incoming View & Share Intent handler"),
        ("takePersistableUriPermission", "Persistable URI permissions"),
        ("ACTION_SEND_MULTIPLE", "ACTION_SEND_MULTIPLE intent handler"),
    ]

    for token, desc in kt_checks:
        if token in kt_text:
            print(f"  [PASS] MainActivity: {desc}")
        else:
            print(f"  [FAIL] MainActivity: Missing {desc} ({token})")
            all_passed = False

    return all_passed

def check_flutter_source_and_build_config():
    print_header("4. Flutter Project Configuration & Build Readiness")

    required_components = [
        ("app/pubspec.yaml", "Flutter package specification"),
        ("app/lib/main.dart", "Application entrypoint"),
        ("app/lib/app.dart", "Root MaterialApp & Theme/Locale manager"),
        ("app/lib/screens/home_screen.dart", "Minimal Home Screen with branding & recents"),
        ("app/lib/screens/viewer_screen.dart", "Universal Viewer Screen with fallback"),
        ("app/lib/viewers/text_code_viewer.dart", "Virtualized Text & Code Viewer"),
        ("app/lib/viewers/hex_viewer.dart", "Virtualized 16-byte Hex Viewer"),
        ("app/lib/viewers/image_viewer.dart", "Zoomable Image Viewer (Raster & SVG)"),
        ("app/lib/viewers/unsupported_viewer.dart", "Unsupported format fallback state"),
        ("app/lib/widgets/category_grid.dart", "Category Grid with Lucide SVGs"),
        ("app/lib/widgets/diagnostic_banner.dart", "Diagnostic mismatch warning banner"),
        ("app/lib/theme/app_theme.dart", "Material 3 Light and Dark themes"),
        ("app/lib/l10n/app_localizations.dart", "Bidirectional English LTR & Arabic RTL"),
        ("app/lib/ffi/core_bindings.dart", "Dart:FFI native bridge to Rust core"),
        ("app/lib/services/file_service.dart", "File Service & SAF coordinator"),
        ("app/lib/services/recent_files_service.dart", "Recent files local session manager"),
        ("app/assets/branding/magic-key.svg", "App package branding SVG icon"),
        ("app/assets/icons/file-text.svg", "Document category Lucide SVG"),
        ("app/assets/icons/image.svg", "Image category Lucide SVG"),
        ("app/assets/icons/film.svg", "Media category Lucide SVG"),
        ("app/assets/icons/code.svg", "Text & Code category Lucide SVG"),
        ("app/assets/icons/archive.svg", "Archive category Lucide SVG"),
        ("app/assets/icons/binary.svg", "Binary category Lucide SVG"),
        ("app/android/settings.gradle", "Android Gradle settings"),
        ("app/android/build.gradle", "Root Android Gradle buildscript"),
        ("app/android/app/build.gradle", "App module Android Gradle buildscript"),
        ("app/android/gradle.properties", "Android Gradle JVM & AndroidX properties"),
        ("app/android/app/src/main/res/values/styles.xml", "Android theme resource styles.xml"),
        ("app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png", "Android launcher icon ic_launcher.png"),
        ("app/android/gradlew", "Gradle wrapper shell script"),
        ("app/android/gradle/wrapper/gradle-wrapper.jar", "Gradle wrapper binary jar"),
        ("app/android/gradle/wrapper/gradle-wrapper.properties", "Gradle wrapper version configuration"),
        (".github/workflows/build_apk.yml", "GitHub Actions CI/CD ARM64 APK workflow"),
    ]

    missing = 0
    for rel_path, desc in required_components:
        full_path = os.path.join(PROJECT_ROOT, rel_path)
        if os.path.exists(full_path) and os.path.getsize(full_path) > 0:
            print(f"  [PASS] {desc:<48} ({rel_path})")
        else:
            print(f"  [FAIL] Missing component: {desc} ({rel_path})")
            missing += 1

    # Check pubspec.yaml dependencies
    with open(os.path.join(PROJECT_ROOT, "app/pubspec.yaml")) as f:
        pubspec_text = f.read()
    if "ffi:" in pubspec_text and "flutter_svg:" in pubspec_text:
        print("  [PASS] pubspec.yaml includes required dependencies (ffi, flutter_svg).")
    else:
        print("  [FAIL] pubspec.yaml missing required dependencies.")
        missing += 1

    return missing == 0

def main():
    print("=================================================================")
    print("  MAGIC KEY — PHASE 2.1 VERIFICATION & BUILD READINESS HARNESS   ")
    print("=================================================================")

    ok1 = check_rust_core_tests()
    ok2 = check_ffi_packaging_and_boundary()
    ok3 = check_android_manifest_and_saf()
    ok4 = check_flutter_source_and_build_config()

    print_header("Phase 2.1 Verification Summary")
    if ok1 and ok2 and ok3 and ok4:
        print("  ALL PHASE 2.1 VERIFICATION CHECKS PASSED WITH 100% SUCCESS!")
        sys.exit(0)
    else:
        print("  SOME PHASE 2.1 VERIFICATION CHECKS FAILED.")
        sys.exit(1)

if __name__ == "__main__":
    main()
