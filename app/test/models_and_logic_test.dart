import 'package:flutter_test/flutter_test.dart';
import 'package:magickey/models/detection_result.dart';
import 'package:magickey/models/hex_chunk.dart';
import 'package:magickey/models/file_source.dart';

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
  });
}
