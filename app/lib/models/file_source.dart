import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Structured text content containing decoded string and truncation metadata.
class TextContent {
  final String text;
  final bool isTruncated;
  final int bytesRead;

  const TextContent({
    required this.text,
    required this.isTruncated,
    required this.bytesRead,
  });
}

/// Finds the safe byte length for UTF-8 decoding, trimming any incomplete trailing sequence
/// if and only if the content was truncated at the buffer boundary.
int findUtf8SafeLength(Uint8List bytes, {required bool isTruncated}) {
  if (!isTruncated || bytes.isEmpty) {
    return bytes.length;
  }

  // Inspect the last 1 to 4 bytes for an incomplete multi-byte sequence
  for (int i = 1; i <= 4 && i <= bytes.length; i++) {
    final byte = bytes[bytes.length - i];
    // If ASCII byte (0xxxxxxx), sequence terminates normally
    if ((byte & 0x80) == 0) {
      break;
    }
    // If leading byte (11xxxxxx)
    if ((byte & 0xC0) != 0x80) {
      int expectedLength;
      if ((byte & 0xE0) == 0xC0) {
        expectedLength = 2; // 110xxxxx
      } else if ((byte & 0xF0) == 0xE0) {
        expectedLength = 3; // 1110xxxx
      } else if ((byte & 0xF8) == 0xF0) {
        expectedLength = 4; // 11110xxx
      } else {
        // Invalid UTF-8 leading byte (0xF8..0xFF)
        break;
      }

      // 'i' bytes are currently available from this leading byte to the buffer end
      if (i < expectedLength) {
        // Multi-byte character split across truncation boundary!
        // Exclude the trailing 'i' bytes so no replacement character is produced.
        return bytes.length - i;
      }
      break;
    }
  }

  return bytes.length;
}

/// Abstract file source decoupling the UI and viewers from underlying OS storage mechanisms.
abstract class FileSource {
  String get name;
  int get size;
  String? get path;
  String? get uri;

  Future<Uint8List> readHeader(int maxBytes);
  Future<Uint8List> readChunk(int offset, int length);

  /// Bounded text content reader returning decoded text and boundary truncation metadata.
  Future<TextContent> readTextContent({int maxBytes = 1048576}) async {
    bool isTruncated = false;
    Uint8List chunk;

    if (size > 0) {
      if (size > maxBytes) {
        isTruncated = true;
        chunk = await readChunk(0, maxBytes);
      } else {
        isTruncated = false;
        chunk = await readChunk(0, size);
      }
    } else {
      // Size unknown: probe with maxBytes + 1 bounded read
      final probe = await readChunk(0, maxBytes + 1);
      if (probe.length > maxBytes) {
        isTruncated = true;
        chunk = probe.sublist(0, maxBytes);
      } else {
        isTruncated = false;
        chunk = probe;
      }
    }

    if (size > 0 && chunk.isEmpty) {
      throw StateError('File stream yielded 0 bytes despite expected size ($size B)');
    }

    final safeLength = findUtf8SafeLength(chunk, isTruncated: isTruncated);
    final safeBytes = safeLength == chunk.length ? chunk : chunk.sublist(0, safeLength);
    final text = utf8.decode(safeBytes, allowMalformed: true);

    return TextContent(
      text: text,
      isTruncated: isTruncated,
      bytesRead: safeLength,
    );
  }

  /// Convenience text reader returning decoded string.
  Future<String> readText({int maxBytes = 1048576}) async {
    final res = await readTextContent(maxBytes: maxBytes);
    return res.text;
  }

  String get formattedSize {
    if (size < 0) return 'Unknown size';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get extensionHint {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < name.length - 1) {
      return name.substring(dotIndex + 1).toLowerCase();
    }
    return '';
  }
}

/// FileSource backed by a local POSIX file path.
class LocalPathFileSource extends FileSource {
  @override
  final String path;
  @override
  final String name;
  @override
  final int size;

  LocalPathFileSource({
    required this.path,
    required this.name,
    required this.size,
  });

  @override
  String? get uri => null;

  @override
  Future<Uint8List> readHeader(int maxBytes) async {
    try {
      final bytes = await MethodChannel('com.magickey/saf').invokeMethod<Uint8List>(
        'readPathHeader',
        {'path': path, 'maxBytes': maxBytes},
      );
      return bytes ?? Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  @override
  Future<Uint8List> readChunk(int offset, int length) async {
    final bytes = await MethodChannel('com.magickey/saf').invokeMethod<Uint8List>(
      'readPathChunk',
      {'path': path, 'offset': offset, 'length': length},
    );
    return bytes ?? Uint8List(0);
  }
}

/// FileSource backed by an Android ContentResolver content:// URI.
class AndroidUriFileSource extends FileSource {
  @override
  final String uri;
  @override
  final String name;
  @override
  final int size;

  static const MethodChannel _safChannel = MethodChannel('com.magickey/saf');

  AndroidUriFileSource({
    required this.uri,
    required this.name,
    required this.size,
  });

  @override
  String? get path => null;

  @override
  Future<Uint8List> readHeader(int maxBytes) async {
    try {
      final bytes = await _safChannel.invokeMethod<Uint8List>(
        'readUriHeader',
        {'uri': uri, 'maxBytes': maxBytes},
      );
      return bytes ?? Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  @override
  Future<Uint8List> readChunk(int offset, int length) async {
    final bytes = await _safChannel.invokeMethod<Uint8List>(
      'readUriChunk',
      {'uri': uri, 'offset': offset, 'length': length},
    );
    return bytes ?? Uint8List(0);
  }
}
