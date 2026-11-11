import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Abstract file source decoupling the UI and viewers from underlying OS storage mechanisms.
abstract class FileSource {
  String get name;
  int get size;
  String? get path;
  String? get uri;

  Future<Uint8List> readHeader(int maxBytes);
  Future<Uint8List> readChunk(int offset, int length);
  Future<String> readText({int maxBytes = 1048576}); // Default 1 MB text ceiling

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
    // Implemented via standard dart:io or native channel
    final bytes = await MethodChannel('com.magickey/saf').invokeMethod<Uint8List>(
      'readPathHeader',
      {'path': path, 'maxBytes': maxBytes},
    );
    return bytes ?? Uint8List(0);
  }

  @override
  Future<Uint8List> readChunk(int offset, int length) async {
    final bytes = await MethodChannel('com.magickey/saf').invokeMethod<Uint8List>(
      'readPathChunk',
      {'path': path, 'offset': offset, 'length': length},
    );
    return bytes ?? Uint8List(0);
  }

  @override
  Future<String> readText({int maxBytes = 1048576}) async {
    final toRead = size > 0 ? size.clamp(0, maxBytes) : maxBytes;
    final chunk = await readChunk(0, toRead);
    return String.fromCharCodes(chunk);
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
    try {
      final bytes = await _safChannel.invokeMethod<Uint8List>(
        'readUriChunk',
        {'uri': uri, 'offset': offset, 'length': length},
      );
      return bytes ?? Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  @override
  Future<String> readText({int maxBytes = 1048576}) async {
    final toRead = size > 0 ? size.clamp(0, maxBytes) : maxBytes;
    final chunk = await readChunk(0, toRead);
    return String.fromCharCodes(chunk);
  }
}
