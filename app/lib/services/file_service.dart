import 'dart:async';
import 'package:flutter/services.dart';
import '../ffi/core_bindings.dart';
import '../models/detection_result.dart';
import '../models/file_source.dart';

/// Central service managing file selection, Android SAF, and format identification.
class FileService {
  static const MethodChannel _safChannel = MethodChannel('com.magickey/saf');
  static final FileService instance = FileService._internal();
  factory FileService() => instance;

  final CoreBindings _bindings = CoreBindings.instance;

  final StreamController<FileSource> _incomingFileController =
      StreamController<FileSource>.broadcast();

  /// Stream of incoming files delivered via warm-start intents (ACTION_VIEW, ACTION_SEND, ACTION_SEND_MULTIPLE).
  Stream<FileSource> get onIncomingFile => _incomingFileController.stream;

  String? _lastProcessedUri;
  DateTime? _lastProcessedTime;

  FileService._internal() {
    _safChannel.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onNewIntentUri') {
      final uriStr = call.arguments as String?;
      if (uriStr != null && uriStr.isNotEmpty) {
        await _processIncomingUri(uriStr, isWarmStart: true);
      }
    }
  }

  /// Processes an incoming URI from cold or warm start with deduplication.
  Future<FileSource?> _processIncomingUri(String uriStr, {required bool isWarmStart}) async {
    final now = DateTime.now();
    if (_lastProcessedUri == uriStr &&
        _lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inMilliseconds < 1000) {
      // Ignore duplicate trigger within 1000ms
      return null;
    }
    _lastProcessedUri = uriStr;
    _lastProcessedTime = now;

    final source = await resolveUriToFileSource(uriStr);
    if (source != null && isWarmStart) {
      _incomingFileController.add(source);
    }
    return source;
  }

  /// Resolves a content:// or file:// URI string to an AndroidUriFileSource with metadata.
  Future<FileSource?> resolveUriToFileSource(String uriStr) async {
    try {
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

  /// Launches Android Storage Access Framework to pick a file with optional MIME filter.
  Future<FileSource?> pickFile({String mimeType = '*/*'}) async {
    try {
      final res = await _safChannel.invokeMapMethod<String, dynamic>(
        'openDocument',
        {'mimeType': mimeType},
      );
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

  /// Checks if the app was launched by an external application via ACTION_VIEW or ACTION_SEND (Cold Start).
  Future<FileSource?> checkInitialIntent() async {
    try {
      final uriStr = await _safChannel.invokeMethod<String>('getInitialIntentUri');
      if (uriStr == null || uriStr.isEmpty) return null;
      return await _processIncomingUri(uriStr, isWarmStart: false);
    } catch (_) {
      return null;
    }
  }

  /// Identifies the format of a FileSource using the Rust core detection engine.
  Future<DetectionResult> identifyFile(FileSource source) async {
    try {
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
    } catch (e) {
      return DetectionResult(
        formatId: 'unknown_binary',
        displayName: 'Unclassified Stream',
        mimeType: 'application/octet-stream',
        category: 'binary',
        confidence: 'low',
        detectionMethod: 'fallback',
        suggestedViewer: 'hex',
        details: 'Detection failed defensively: $e',
      );
    }
  }
}
