#!/usr/bin/env python3
"""
Magic Key — Phase 1 Test & Verification Harness
Runs all automated unit, integration, and FFI tests for the Phase 1 core.
"""

import os
import sys
import tempfile
import subprocess
import json

PROJECT_ROOT = "/storage/emulated/0/ANTYEE/MagicKey"
CARGO_TARGET_DIR = "/data/data/com.termux/files/home/.cargo_targets/magickey"

def print_banner(text):
    print("\n" + "=" * 65)
    print(f" {text}")
    print("=" * 65)

def run_cargo_tests():
    print_banner("1. Running Rust Automated Test Suite (Cargo Test)")
    cmd = [
        "cargo", "test", "--offline",
        "--manifest-path", os.path.join(PROJECT_ROOT, "core/Cargo.toml"),
        "--", "--nocapture"
    ]
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = CARGO_TARGET_DIR

    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    print(res.stdout)
    if res.returncode != 0:
        print(res.stderr)
        print("  [FAIL] Cargo test suite failed.")
        return False
    print("  [PASS] All Rust unit and integration tests passed cleanly.")
    return True

def run_synthetic_fixtures_and_ffi_tests():
    print_banner("2. End-to-End Fixture & C-ABI FFI Verification")
    import ctypes

    so_path = os.path.join(CARGO_TARGET_DIR, "release/libmagickey_core.so")
    if not os.path.exists(so_path):
        print("  [INFO] Building release libmagickey_core.so...")
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = CARGO_TARGET_DIR
        subprocess.run(["cargo", "build", "--release", "--offline", "--manifest-path", os.path.join(PROJECT_ROOT, "core/Cargo.toml")], env=env, check=True)

    lib = ctypes.CDLL(so_path)
    lib.magickey_detect_file.argtypes = [ctypes.c_char_p]
    lib.magickey_detect_file.restype = ctypes.c_char_p
    lib.magickey_read_hex_chunk.argtypes = [ctypes.c_char_p, ctypes.c_uint64, ctypes.c_size_t]
    lib.magickey_read_hex_chunk.restype = ctypes.c_char_p

    fixtures = [
        ("test.pdf", b"%PDF-1.7\r\nstream\r\n", "pdf", "document"),
        ("test.png", b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", "png", "image"),
        ("test.jpg", b"\xFF\xD8\xFF\xE0\x00\x10JFIF\x00", "jpeg", "image"),
        ("test.gif", b"GIF89a\x01\x00\x01\x00", "gif", "image"),
        ("test.webp", b"RIFF\x14\x00\x00\x00WEBPVP8 ", "webp", "image"),
        ("test.zip", b"PK\x03\x04\x14\x00\x00\x00", "zip", "archive"),
        ("test.gz", b"\x1F\x8B\x08\x00\x00\x00", "gzip", "archive"),
        ("test.mp3", b"ID3\x04\x00\x00\x00\x00\x00\x00", "mp3", "media"),
        ("test.wav", b"RIFF\x24\x00\x00\x00WAVEfmt ", "wav", "media"),
        ("test.mp4", b"\x00\x00\x00\x18ftypisom", "mp4", "media"),
        ("test.flac", b"fLaC\x00\x00\x00\x22", "flac", "media"),
        ("test.ogg", b"OggS\x00\x02\x00\x00", "ogg", "media"),
        ("test.elf", b"\x7FELF\x02\x01\x01\x00", "elf", "hex"),
        ("test.dex", b"dex\n039\x00", "dex", "hex"),
        ("test.sqlite", b"SQLite format 3\x00", "sqlite", "hex"),
        ("test.json", b'{"project": "MagicKey", "active": true}', "json", "text_code"),
        ("test.svg", b'<svg viewBox="0 0 24 24"><path d="M0 0"/></svg>', "svg", "image"),
        ("test.md", b'# Magic Key\nUniversal file opener.\n', "markdown", "text_code"),
        ("test.sh", b'#!/bin/bash\necho "Hello"\n', "shell", "text_code"),
        ("empty.bin", b'', "empty", "hex"),
    ]

    passed = 0
    with tempfile.TemporaryDirectory() as tmpdir:
        for fname, data, expected_id, expected_viewer in fixtures:
            fpath = os.path.join(tmpdir, fname)
            with open(fpath, "wb") as f:
                f.write(data)

            res_ptr = lib.magickey_detect_file(fpath.encode("utf-8"))
            if not res_ptr:
                print(f"  [FAIL] {fname}: FFI returned null pointer")
                continue

            res = json.loads(res_ptr.decode("utf-8"))
            if res.get("format_id") == expected_id and res.get("suggested_viewer") == expected_viewer:
                print(f"  [PASS] {fname:<15} -> Detected: {res['format_id']:<10} | Viewer: {res['suggested_viewer']:<10} ({res['confidence']})")
                passed += 1
            else:
                print(f"  [FAIL] {fname:<15} -> Expected ({expected_id}, {expected_viewer}) but got ({res.get('format_id')}, {res.get('suggested_viewer')})")

        # Test Misleading Extension
        misleading_path = os.path.join(tmpdir, "evil_document.png")
        with open(misleading_path, "wb") as f:
            f.write(b"%PDF-1.7\r\nActual PDF masquerading as PNG\r\n")
        res_ptr = lib.magickey_detect_file(misleading_path.encode("utf-8"))
        res = json.loads(res_ptr.decode("utf-8"))
        if res.get("format_id") == "pdf" and res.get("suggested_viewer") == "document":
            print(f"  [PASS] Misleading Ext  -> evil_document.png correctly identified as {res['format_id']} (High confidence)")
            passed += 1
        else:
            print(f"  [FAIL] Misleading Ext  -> Failed to detect actual PDF in PNG-named file")

        # Test Hex Viewer Chunking
        hex_target = os.path.join(tmpdir, "large_hex_test.bin")
        chunk_data = b"0123456789ABCDEF" * 16 # 256 bytes
        with open(hex_target, "wb") as f:
            f.write(chunk_data)

        hex_ptr = lib.magickey_read_hex_chunk(hex_target.encode("utf-8"), 32, 64)
        hex_res = json.loads(hex_ptr.decode("utf-8"))
        if len(hex_res.get("rows", [])) == 4 and hex_res.get("bytes_read") == 64:
            print(f"  [PASS] Hex Chunk Read  -> Successfully read 64 bytes (4 rows) at offset 32")
            passed += 1
        else:
            print(f"  [FAIL] Hex Chunk Read  -> Unexpected chunk rows count: {len(hex_res.get('rows', []))}")

    total_fixtures = len(fixtures) + 2
    print(f"\n  Result: {passed}/{total_fixtures} FFI fixture tests passed.")
    return passed == total_fixtures

def main():
    print("=================================================================")
    print("  MAGIC KEY — PHASE 1 AUTOMATED CORE VERIFICATION HARNESS       ")
    print("=================================================================")
    ok1 = run_cargo_tests()
    ok2 = run_synthetic_fixtures_and_ffi_tests()

    print_banner("Verification Summary")
    if ok1 and ok2:
        print("  ALL PHASE 1 AUTOMATED TESTS PASSED SUCCESSFULLY! (100% PASS RATE)")
        sys.exit(0)
    else:
        print("  SOME TESTS FAILED.")
        sys.exit(1)

if __name__ == "__main__":
    main()
