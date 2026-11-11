import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:magickey/ffi/core_bindings.dart';

void main() {
  group('Rust Core Dart:FFI Live Runtime Integration', () {
    test('Load native library and execute real Rust core functions at runtime', () {
      final isNativeAvailable = File('libmagickey_core.so').existsSync() ||
          File('../target/release/libmagickey_core.so').existsSync() ||
          File('../../target/release/libmagickey_core.so').existsSync() ||
          Platform.environment.containsKey('MAGICKEY_CORE_LIB');

      if (!isNativeAvailable) {
        // Skip execution if host binary is not in build path
        return;
      }

      final bindings = CoreBindings.instance;

      // 1. Real PDF buffer detection
      final pdfBytes = Uint8List.fromList('%PDF-1.7\r\nstream\r\n'.codeUnits);
      final pdfResult = bindings.detectBuffer(pdfBytes);
      expect(pdfResult.formatId, 'pdf');
      expect(pdfResult.displayName, 'Portable Document Format');
      expect(pdfResult.suggestedViewer, 'document');
      expect(pdfResult.isHighConfidence, isTrue);

      // 2. Misleading extension resolution (magic bytes take precedence)
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final pngResult = bindings.detectBuffer(pngBytes, extensionHint: 'txt');
      expect(pngResult.formatId, 'png');

      // 3. Complete format registry extraction
      final registry = bindings.getRegistry();
      expect(registry, isNotEmpty);
      expect(registry.length, greaterThanOrEqualTo(35));

      // 4. Hex chunk formatting via Rust engine
      final sampleBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]);
      final hexChunk = bindings.formatHexChunk(sampleBytes, offset: 0, totalSize: 8);
      expect(hexChunk.rows, isNotEmpty);
      expect(hexChunk.rows.first.formattedLine, contains('50 4B 03 04'));
      expect(hexChunk.isEof, isTrue);
    });
  });
}
