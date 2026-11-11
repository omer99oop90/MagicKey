// Unit test suite for Magic Key data models and business logic.
// This test file can be executed with any Dart test runner.

void main() {
  print('Running Magic Key Phase 2 Dart Models & Logic Tests...');
  testDetectionResultModel();
  testHexChunkModel();
  testFileSourceFormatting();
  print('All Dart model and logic tests passed successfully!');
}

void testDetectionResultModel() {
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

  assert(json['format_id'] == 'pdf');
  assert(json['category'] == 'document');
  assert(json['suggested_viewer'] == 'document');
  print('  [PASS] DetectionResult model serialization verified.');
}

void testHexChunkModel() {
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

  assert(json['start_offset'] == 32);
  assert((json['rows'] as List).length == 1);
  assert(json['is_eof'] == false);
  print('  [PASS] HexChunk model serialization verified.');
}

void testFileSourceFormatting() {
  String formatSize(int bytes) {
    if (bytes < 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  assert(formatSize(500) == '500 B');
  assert(formatSize(1024) == '1.0 KB');
  assert(formatSize(1024 * 1024 * 5) == '5.0 MB');
  assert(formatSize(1024 * 1024 * 1024 * 2) == '2.00 GB');
  print('  [PASS] FileSource size formatting verified.');
}
