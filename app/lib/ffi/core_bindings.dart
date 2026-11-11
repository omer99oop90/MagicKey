import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import '../models/detection_result.dart';
import '../models/hex_chunk.dart';

// Native FFI Typedefs
typedef MagickeyDetectFileNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef MagickeyDetectFileDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef MagickeyDetectBufferNative = Pointer<Utf8> Function(
  Pointer<Uint8> buffer,
  IntPtr len,
  Pointer<Utf8> ext,
);
typedef MagickeyDetectBufferDart = Pointer<Utf8> Function(
  Pointer<Uint8> buffer,
  int len,
  Pointer<Utf8> ext,
);

typedef MagickeyReadHexChunkNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Uint64 offset,
  IntPtr maxBytes,
);
typedef MagickeyReadHexChunkDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  int offset,
  int maxBytes,
);

typedef MagickeyFormatHexChunkNative = Pointer<Utf8> Function(
  Pointer<Uint8> buffer,
  IntPtr len,
  Uint64 offset,
  Uint64 totalSize,
);
typedef MagickeyFormatHexChunkDart = Pointer<Utf8> Function(
  Pointer<Uint8> buffer,
  int len,
  int offset,
  int totalSize,
);

typedef MagickeyGetRegistryJsonNative = Pointer<Utf8> Function();
typedef MagickeyGetRegistryJsonDart = Pointer<Utf8> Function();

typedef MagickeyFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef MagickeyFreeStringDart = void Function(Pointer<Utf8> ptr);

/// High-level Dart interface to the Magic Key Rust core.
class CoreBindings {
  static CoreBindings? _instance;
  final DynamicLibrary _lib;

  late final MagickeyDetectFileDart _detectFile;
  late final MagickeyDetectBufferDart _detectBuffer;
  late final MagickeyReadHexChunkDart _readHexChunk;
  late final MagickeyFormatHexChunkDart _formatHexChunk;
  late final MagickeyGetRegistryJsonDart _getRegistryJson;
  late final MagickeyFreeStringDart _freeString;

  CoreBindings._(this._lib) {
    _detectFile = _lib
        .lookup<NativeFunction<MagickeyDetectFileNative>>('magickey_detect_file')
        .asFunction();

    _detectBuffer = _lib
        .lookup<NativeFunction<MagickeyDetectBufferNative>>('magickey_detect_buffer')
        .asFunction();

    _readHexChunk = _lib
        .lookup<NativeFunction<MagickeyReadHexChunkNative>>('magickey_read_hex_chunk')
        .asFunction();

    _formatHexChunk = _lib
        .lookup<NativeFunction<MagickeyFormatHexChunkNative>>('magickey_format_hex_chunk')
        .asFunction();

    _getRegistryJson = _lib
        .lookup<NativeFunction<MagickeyGetRegistryJsonNative>>('magickey_get_registry_json')
        .asFunction();

    _freeString = _lib
        .lookup<NativeFunction<MagickeyFreeStringNative>>('magickey_free_string')
        .asFunction();
  }

  /// Singleton instance loader.
  static CoreBindings get instance {
    _instance ??= CoreBindings._(_loadLibrary());
    return _instance!;
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      try {
        return DynamicLibrary.open('libmagickey_core.so');
      } catch (_) {
        // Fallback to absolute or current execution path
        return DynamicLibrary.process();
      }
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('magickey_core.dll');
    } else if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Magic Key core library not supported on ${Platform.operatingSystem}');
  }

  /// Detects format from a filesystem path.
  DetectionResult detectFile(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      final resPtr = _detectFile(pathPtr);
      if (resPtr.address == 0) {
        throw StateError('Rust core returned null pointer for detectFile');
      }
      try {
        final jsonStr = resPtr.toDartString();
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        return DetectionResult.fromJson(map);
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Detects format from an in-memory buffer (e.g. from Android ContentResolver stream).
  DetectionResult detectBuffer(Uint8List buffer, {String? extensionHint}) {
    final Pointer<Uint8> bufferPtr = calloc<Uint8>(buffer.length);
    final Pointer<Utf8> extPtr = extensionHint != null && extensionHint.isNotEmpty
        ? extensionHint.toNativeUtf8()
        : nullptr;

    try {
      final byteList = bufferPtr.asTypedList(buffer.length);
      byteList.setAll(0, buffer);

      final resPtr = _detectBuffer(bufferPtr, buffer.length, extPtr);
      if (resPtr.address == 0) {
        throw StateError('Rust core returned null pointer for detectBuffer');
      }
      try {
        final jsonStr = resPtr.toDartString();
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        return DetectionResult.fromJson(map);
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(bufferPtr);
      if (extPtr != nullptr) {
        calloc.free(extPtr);
      }
    }
  }

  /// Reads a virtualized Hex chunk from a file path.
  HexChunk readHexChunk(String path, {int offset = 0, int maxBytes = 256}) {
    final pathPtr = path.toNativeUtf8();
    try {
      final resPtr = _readHexChunk(pathPtr, offset, maxBytes);
      if (resPtr.address == 0) {
        throw StateError('Rust core returned null pointer for readHexChunk');
      }
      try {
        final jsonStr = resPtr.toDartString();
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        return HexChunk.fromJson(map);
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Formats an arbitrary in-memory byte buffer as a canonical Hex chunk.
  HexChunk formatHexChunk(Uint8List buffer, {int offset = 0, required int totalSize}) {
    final Pointer<Uint8> bufferPtr = calloc<Uint8>(buffer.length);
    try {
      final byteList = bufferPtr.asTypedList(buffer.length);
      byteList.setAll(0, buffer);

      final resPtr = _formatHexChunk(bufferPtr, buffer.length, offset, totalSize);
      if (resPtr.address == 0) {
        throw StateError('Rust core returned null pointer for formatHexChunk');
      }
      try {
        final jsonStr = resPtr.toDartString();
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        return HexChunk.fromJson(map);
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(bufferPtr);
    }
  }
}
