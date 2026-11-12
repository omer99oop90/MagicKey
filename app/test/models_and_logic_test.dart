import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:magickey/models/detection_result.dart';
import 'package:magickey/models/hex_chunk.dart';
import 'package:magickey/models/file_source.dart';
import 'package:magickey/widgets/category_grid.dart';

void main() {
  group('Magic Key Model & Logic Unit Tests', () {
    test('DetectionResult model deserialization', () {
      final json = {
        'format_id': 'pdf',
        'display_name': 'Portable Document Format',
        'mime_type': 'application/pdf',
        'category': 'document',
        'confidence': 'high',
        'detection_method': 'magic_bytes',
        'suggested_viewer': 'document',
        'details': 'Positively identified via primary magic byte signature.',
      };

      final result = DetectionResult.fromJson(json);
      expect(result.formatId, 'pdf');
      expect(result.displayName, 'Portable Document Format');
      expect(result.mimeType, 'application/pdf');
      expect(result.category, 'document');
      expect(result.confidence, 'high');
      expect(result.suggestedViewer, 'document');
      expect(result.isHighConfidence, isTrue);
    });

    test('HexChunk model deserialization and row counts', () {
      final json = {
        'start_offset': 32,
        'bytes_read': 16,
        'total_file_size': 1024,
        'rows': [
          {
            'offset': 32,
            'byte_count': 16,
            'hex_dump': '50 4B 03 04 14 00 00 00  08 00 00 00 00 00 00 00',
            'ascii_dump': '|PK..............|',
            'formatted_line': '00000020  50 4B 03 04 14 00 00 00  08 00 00 00 00 00 00 00  |PK..............|',
          }
        ],
        'is_eof': false,
      };

      final chunk = HexChunk.fromJson(json);
      expect(chunk.startOffset, 32);
      expect(chunk.bytesRead, 16);
      expect(chunk.totalFileSize, 1024);
      expect(chunk.rows.length, 1);
      expect(chunk.rows.first.offset, 32);
      expect(chunk.isEof, isFalse);
    });

    test('FileSource human-readable size formatting', () {
      final sourceBytes = AndroidUriFileSource(uri: 'content://test', name: 'small.bin', size: 500);
      expect(sourceBytes.formattedSize, '500 B');

      final sourceKb = AndroidUriFileSource(uri: 'content://test', name: 'medium.bin', size: 1024);
      expect(sourceKb.formattedSize, '1.0 KB');

      final sourceMb = AndroidUriFileSource(uri: 'content://test', name: 'large.bin', size: 5 * 1024 * 1024);
      expect(sourceMb.formattedSize, '5.0 MB');

      final sourceGb = AndroidUriFileSource(uri: 'content://test', name: 'huge.bin', size: 2 * 1024 * 1024 * 1024);
      expect(sourceGb.formattedSize, '2.00 GB');

      final sourceUnknown = AndroidUriFileSource(uri: 'content://test', name: 'unknown.bin', size: -1);
      expect(sourceUnknown.formattedSize, 'Unknown size');
    });

    test('FileSource extensionHint resolution', () {
      final source = AndroidUriFileSource(uri: 'content://test', name: 'document.PDF', size: 100);
      expect(source.extensionHint, 'pdf');

      final sourceNoExt = AndroidUriFileSource(uri: 'content://test', name: 'README', size: 100);
      expect(sourceNoExt.extensionHint, '');

      final sourceApk = AndroidUriFileSource(uri: 'content://test', name: 'app-release.apk', size: 100);
      expect(sourceApk.extensionHint, 'apk');
    });

    test('CategoryGrid configuration and MIME type filters', () {
      expect(CategoryGrid.categories.length, 6);

      final imageCat = CategoryGrid.categories.firstWhere((c) => c.id == 'image');
      expect(imageCat.mimeType, 'image/*');
      expect(imageCat.formatsHint, contains('PNG'));

      final textCat = CategoryGrid.categories.firstWhere((c) => c.id == 'text_code');
      expect(textCat.mimeType, 'text/*');

      final archiveCat = CategoryGrid.categories.firstWhere((c) => c.id == 'archive');
      expect(archiveCat.formatsHint, contains('ZIP, APK'));
    });

    test('UTF-8 multi-byte decoding handles boundaries and international text', () {
      // 1. Arabic text stream simulation: "المفتاح السحري"
      const arabicText = 'المفتاح السحري';
      final arabicBytes = utf8.encode(arabicText);
      final decoded = utf8.decode(arabicBytes, allowMalformed: true);
      expect(decoded, arabicText);

      // 2. Multi-byte boundary truncation simulation with allowMalformed: true
      // Taking a slice that splits a 2-byte UTF-8 Arabic letter in half
      final truncatedBytes = arabicBytes.sublist(0, 3);
      final decodedTruncated = utf8.decode(truncatedBytes, allowMalformed: true);
      expect(decodedTruncated.isNotEmpty, isTrue);
    });
  });
}
