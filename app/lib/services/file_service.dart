import 'package:flutter/services.dart';
import '../ffi/core_bindings.dart';
import '../models/detection_result.dart';
import '../models/file_source.dart';

/// Central service managing file selection, Android SAF, and format identification.
class FileService {
  static const MethodChannel _safChannel = MethodChannel('com.magickey/saf');
  final CoreBindings _bindings = CoreBindings.instance;

  /// Launches Android Storage Access Framework to pick any file (*/*).
  Future<FileSource?> pickFile() async {
    try {
      final res = await _safChannel.invokeMapMethod<String, dynamic>('openDocument');
      if (res == null) return null;

      final uriStr = res['uri'] as String?;
      final name = res['name'] as String? ?? 'selected_file';
      final size = (res['size'] as num?)?.toInt() ?? -1;

      if (uriStr == null) return null;

      return AndroidUriFileSource(
        uri: uriStr,
        name: name,
        size: size,
      );
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Checks if the app was launched by an external application via ACTION_VIEW or ACTION_SEND.
  Future<FileSource?> checkInitialIntent() async {
    try {
      final uriStr = await _safChannel.invokeMethod<String>('getInitialIntentUri');
      if (uriStr == null || uriStr.isEmpty) return null;

      final metadata = await _safChannel.invokeMapMethod<String, dynamic>(
        'getMetadata',
        {'uri': uriStr},
      );

      final name = metadata?['name'] as String? ?? 'shared_file';
      final size = (metadata?['size'] as num?)?.toInt() ?? -1;

      return AndroidUriFileSource(
        uri: uriStr,
        name: name,
        size: size,
      );
    } catch (_) {
      return null;
    }
  }

  /// Identifies the format of a FileSource using the Rust core detection engine.
  Future<DetectionResult> identifyFile(FileSource source) async {
    // If it's a local filesystem path, call direct file detector
    if (source.path != null && source.path!.isNotEmpty) {
      try {
        return _bindings.detectFile(source.path!);
      } catch (_) {}
    }

    // Otherwise, read bounded 512-byte header and pass to FFI buffer detector
    final header = await source.readHeader(512);
    return _bindings.detectBuffer(
      header,
      extensionHint: source.extensionHint,
    );
  }
}
