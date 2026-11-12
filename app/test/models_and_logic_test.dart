import 'dart:convert';
import 'dart:typed_data';
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
      expect(textCat.formatsHint, contains('Source Code'));

      final mediaCat = CategoryGrid.categories.firstWhere((c) => c.id == 'media');
      expect(mediaCat.mimeType, 'audio/*, video/*');
      expect(mediaCat.formatsHint, contains('Audio & Video'));

      final documentCat = CategoryGrid.categories.firstWhere((c) => c.id == 'document');
      expect(documentCat.mimeType, '*/*');
      expect(documentCat.formatsHint, contains('Plain Text'));

      final archiveCat = CategoryGrid.categories.firstWhere((c) => c.id == 'archive');
      expect(archiveCat.mimeType, '*/*');
      expect(archiveCat.formatsHint, contains('ZIP, APK'));

      final binaryCat = CategoryGrid.categories.firstWhere((c) => c.id == 'binary');
      expect(binaryCat.mimeType, '*/*');
      expect(binaryCat.formatsHint, contains('Hex Engine'));
    });

    test('UTF-8 Boundary Correction: Arabic 2-byte, 3-byte, and 4-byte characters complete decoding', () {
      // 1. Two-byte Arabic characters: "المفتاح السحري"
      const arabicTwoByte = 'المفتاح السحري';
      final b2 = Uint8List.fromList(utf8.encode(arabicTwoByte));
      expect(findUtf8SafeLength(b2, isTruncated: true), b2.length);
      expect(findUtf8SafeLength(b2, isTruncated: false), b2.length);
      expect(utf8.decode(b2, allowMalformed: true), arabicTwoByte);

      // 2. Three-byte characters: "السعر: 100 € ﷽" ('﷽' is U+FDFD = EF B7 BD) and Euro "€"
      const threeByteText = 'السعر: 100 € ﷽';
      final b3 = Uint8List.fromList(utf8.encode(threeByteText));
      expect(findUtf8SafeLength(b3, isTruncated: true), b3.length);
      expect(findUtf8SafeLength(b3, isTruncated: false), b3.length);
      expect(utf8.decode(b3, allowMalformed: true), threeByteText);

      // 3. Four-byte characters: Emojis "🔑 Magic Key 🚀" ('🔑' = F0 9F 94 91, '🚀' = F0 9F 9A 80)
      const fourByteText = '🔑 Magic Key 🚀';
      final b4 = Uint8List.fromList(utf8.encode(fourByteText));
      expect(findUtf8SafeLength(b4, isTruncated: true), b4.length);
      expect(findUtf8SafeLength(b4, isTruncated: false), b4.length);
      expect(utf8.decode(b4, allowMalformed: true), fourByteText);
    });

    test('UTF-8 Boundary Correction: Split characters across truncation boundary do NOT produce U+FFFD', () {
      const prefix = 'مرحبا '; // Arabic "Hello " (11 bytes in UTF-8)
      final prefixBytes = utf8.encode(prefix);

      // Case A: 2-byte Arabic character ('ع' = D8 B9) split across boundary (only 1 byte read)
      final arabicTwoByteChar = utf8.encode('ع'); // [0xD8, 0xB9]
      final splitTwoByte = Uint8List.fromList([...prefixBytes, arabicTwoByteChar[0]]);
      final safeLen2 = findUtf8SafeLength(splitTwoByte, isTruncated: true);
      expect(safeLen2, prefixBytes.length);
      final decoded2 = utf8.decode(splitTwoByte.sublist(0, safeLen2), allowMalformed: true);
      expect(decoded2, prefix);
      expect(decoded2.contains('\uFFFD'), isFalse);

      // Case B: 3-byte character ('€' = E2 82 AC) split with 1 byte read
      final euroBytes = utf8.encode('€'); // [0xE2, 0x82, 0xAC]
      final splitThreeByte1 = Uint8List.fromList([...prefixBytes, euroBytes[0]]);
      final safeLen3a = findUtf8SafeLength(splitThreeByte1, isTruncated: true);
      expect(safeLen3a, prefixBytes.length);
      final decoded3a = utf8.decode(splitThreeByte1.sublist(0, safeLen3a), allowMalformed: true);
      expect(decoded3a, prefix);
      expect(decoded3a.contains('\uFFFD'), isFalse);

      // Case C: 3-byte character ('€') split with 2 bytes read
      final splitThreeByte2 = Uint8List.fromList([...prefixBytes, euroBytes[0], euroBytes[1]]);
      final safeLen3b = findUtf8SafeLength(splitThreeByte2, isTruncated: true);
      expect(safeLen3b, prefixBytes.length);
      final decoded3b = utf8.decode(splitThreeByte2.sublist(0, safeLen3b), allowMalformed: true);
      expect(decoded3b, prefix);
      expect(decoded3b.contains('\uFFFD'), isFalse);

      // Case D: 4-byte character ('🔑' = F0 9F 94 91) split with 1, 2, and 3 bytes read
      final keyBytes = utf8.encode('🔑'); // [0xF0, 0x9F, 0x94, 0x91]
      for (int i = 1; i <= 3; i++) {
        final splitFourByte = Uint8List.fromList([...prefixBytes, ...keyBytes.sublist(0, i)]);
        final safeLen4 = findUtf8SafeLength(splitFourByte, isTruncated: true);
        expect(safeLen4, prefixBytes.length);
        final decoded4 = utf8.decode(splitFourByte.sublist(0, safeLen4), allowMalformed: true);
        expect(decoded4, prefix);
        expect(decoded4.contains('\uFFFD'), isFalse);
      }
    });

    test('UTF-8 Boundary Correction: Genuinely malformed UTF-8 sequences preserve U+FFFD in body', () {
      // Stream containing invalid byte 0xFF inside printable text: "Hello\xFFWorld"
      final malformedBody = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0x57, 0x6F, 0x72, 0x6C, 0x64]);
      final safeLen = findUtf8SafeLength(malformedBody, isTruncated: true);
      expect(safeLen, malformedBody.length);
      final decoded = utf8.decode(malformedBody.sublist(0, safeLen), allowMalformed: true);
      expect(decoded, 'Hello\uFFFDWorld');
      expect(decoded.contains('\uFFFD'), isTrue);

      // Orphaned continuation byte 0x80 inside Arabic text: "م\x80ر"
      final malformedArabic = Uint8List.fromList([0xD9, 0x85, 0x80, 0xD8, 0xB1]);
      final safeLenAr = findUtf8SafeLength(malformedArabic, isTruncated: true);
      expect(safeLenAr, malformedArabic.length);
      final decodedAr = utf8.decode(malformedArabic.sublist(0, safeLenAr), allowMalformed: true);
      expect(decodedAr, 'م\uFFFDر');
    });

    test('UTF-8 Boundary Correction: File ending exactly at reading boundary decodes completely without data loss', () {
      // 1. Exactly at boundary with complete 2-byte Arabic word
      const textAtBoundary = 'نهاية الملف بالضبط';
      final bytesAtBoundary = Uint8List.fromList(utf8.encode(textAtBoundary));

      // When isTruncated: false, boundary trimmer must NOT discard the last character
      final safeLenNotTruncated = findUtf8SafeLength(bytesAtBoundary, isTruncated: false);
      expect(safeLenNotTruncated, bytesAtBoundary.length);
      final decodedNotTruncated = utf8.decode(bytesAtBoundary.sublist(0, safeLenNotTruncated), allowMalformed: true);
      expect(decodedNotTruncated, textAtBoundary);

      // When isTruncated: true, but the sequence at boundary is complete
      final safeLenTruncated = findUtf8SafeLength(bytesAtBoundary, isTruncated: true);
      expect(safeLenTruncated, bytesAtBoundary.length);
      final decodedTruncated = utf8.decode(bytesAtBoundary.sublist(0, safeLenTruncated), allowMalformed: true);
      expect(decodedTruncated, textAtBoundary);
    });
  });
}
