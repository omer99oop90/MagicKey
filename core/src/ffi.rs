//! C-ABI Foreign Function Interface (FFI) for Flutter / Dart integration.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

use crate::engines::hex::HexEngine;
use crate::file_detection::FileDetector;
use crate::format_registry::FormatRegistry;

/// Detects format of a file from its filesystem path. Returns a JSON string.
/// Caller must free the returned pointer using `magickey_free_string`.
///
/// # Safety
/// `path_ptr` must be a valid null-terminated C string pointer.
#[no_mangle]
pub unsafe extern "C" fn magickey_detect_file(path_ptr: *const c_char) -> *mut c_char {
    if path_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = match CStr::from_ptr(path_ptr).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let detector = FileDetector::new();
    let result = match detector.detect_file(Path::new(c_str)) {
        Ok(res) => res,
        Err(e) => {
            let err_json = format!(r#"{{"error":"{}"}}"#, e);
            return CString::new(err_json)
                .map(|s| s.into_raw())
                .unwrap_or(std::ptr::null_mut());
        }
    };

    let json = match serde_json::to_string(&result) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    CString::new(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Detects format from a raw in-memory buffer and optional extension hint.
/// Caller must free the returned pointer using `magickey_free_string`.
///
/// # Safety
/// `buffer_ptr` must point to at least `len` valid bytes. If `ext_ptr` is not null,
/// it must point to a valid null-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn magickey_detect_buffer(
    buffer_ptr: *const u8,
    len: usize,
    ext_ptr: *const c_char,
) -> *mut c_char {
    if buffer_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let slice = std::slice::from_raw_parts(buffer_ptr, len);
    let ext_opt = if !ext_ptr.is_null() {
        CStr::from_ptr(ext_ptr).to_str().ok()
    } else {
        None
    };

    let detector = FileDetector::new();
    let result = detector.detect_buffer(slice, ext_opt);

    let json = match serde_json::to_string(&result) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    CString::new(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Reads a bounded chunk of hex-formatted data from a file path. Returns a JSON string.
/// Caller must free the returned pointer using `magickey_free_string`.
///
/// # Safety
/// `path_ptr` must be a valid null-terminated C string pointer.
#[no_mangle]
pub unsafe extern "C" fn magickey_read_hex_chunk(
    path_ptr: *const c_char,
    offset: u64,
    max_bytes: usize,
) -> *mut c_char {
    if path_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = match CStr::from_ptr(path_ptr).to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let chunk_res = HexEngine::read_chunk_from_path(Path::new(c_str), offset, max_bytes);
    let chunk = match chunk_res {
        Ok(c) => c,
        Err(e) => {
            let err_json = format!(r#"{{"error":"{}"}}"#, e);
            return CString::new(err_json)
                .map(|s| s.into_raw())
                .unwrap_or(std::ptr::null_mut());
        }
    };

    let json = match serde_json::to_string(&chunk) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    CString::new(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Formats a raw in-memory byte buffer as a Hex chunk. Returns a JSON string.
/// Caller must free the returned pointer using `magickey_free_string`.
///
/// # Safety
/// `buffer_ptr` must point to at least `len` valid bytes.
#[no_mangle]
pub unsafe extern "C" fn magickey_format_hex_chunk(
    buffer_ptr: *const u8,
    len: usize,
    offset: u64,
    total_size: u64,
) -> *mut c_char {
    if buffer_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let slice = std::slice::from_raw_parts(buffer_ptr, len);
    let chunk = HexEngine::format_chunk_from_bytes(slice, offset, total_size);

    let json = match serde_json::to_string(&chunk) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    CString::new(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Returns the complete format registry database as a JSON string.
/// Caller must free the returned pointer using `magickey_free_string`.
///
/// # Safety
/// The returned pointer is owned by the caller and must be passed to `magickey_free_string`.
#[no_mangle]
pub unsafe extern "C" fn magickey_get_registry_json() -> *mut c_char {
    let registry = FormatRegistry::default();
    let all = registry.list_all();
    let json = match serde_json::to_string(&all) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    CString::new(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Frees a string pointer previously allocated by this library.
///
/// # Safety
/// `ptr` must be a pointer allocated by `CString::into_raw` from this library, or null.
#[no_mangle]
pub unsafe extern "C" fn magickey_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
