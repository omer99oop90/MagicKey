import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magickey/l10n/app_localizations.dart';
import 'package:magickey/screens/home_screen.dart';
import 'package:magickey/screens/image_to_binary_screen.dart';
import 'package:magickey/services/image_binary_codec.dart';

Widget _createTestApp(Widget child) {
  return MaterialApp(
    supportedLocales: const [
      Locale('en', 'US'),
      Locale('ar', 'SA'),
    ],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageHeaderInfo & Color Mode Inspection', () {
    test('Detects PNG RGB and RGBA headers', () {
      // Minimal 26-byte PNG header with colorType = 2 (RGB, 8-bit)
      final pngRgb = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04,
        0x08, 0x02,
      ]);
      final infoRgb = ImageHeaderInfo.inspect(pngRgb);
      expect(infoRgb, isNotNull);
      expect(infoRgb!.formatId, 'PNG');
      expect(infoRgb.colorMode, 'RGB (24-bit)');
      expect(infoRgb.hasAlphaChannel, isFalse);

      // colorType = 6 (RGBA, 8-bit)
      final pngRgba = Uint8List.fromList(pngRgb);
      pngRgba[25] = 6;
      final infoRgba = ImageHeaderInfo.inspect(pngRgba);
      expect(infoRgba!.colorMode, 'RGBA (32-bit)');
      expect(infoRgba.hasAlphaChannel, isTrue);
    });

    test('Detects JPEG and WEBP headers', () {
      final jpegHeader = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x10, 0x00, 0x10, 0x03,
      ]);
      final jpegInfo = ImageHeaderInfo.inspect(jpegHeader);
      expect(jpegInfo, isNotNull);
      expect(jpegInfo!.formatId, 'JPEG');
      expect(jpegInfo.colorMode, contains('YCbCr'));

      final webpHeader = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0x20, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4C,
      ]);
      final webpInfo = ImageHeaderInfo.inspect(webpHeader);
      expect(webpInfo, isNotNull);
      expect(webpInfo!.formatId, 'WEBP');
      expect(webpInfo.hasAlphaChannel, isTrue);
    });
  });

  group('Image-to-Binary & Reconstruction Codec', () {
    // 3x2 synthetic sample image (6 pixels, opaque)
    final sampleRgba = Uint8List.fromList([
      255, 0, 0, 255,     0, 255, 0, 255,     0, 0, 255, 255,
      255, 255, 255, 255, 0, 0, 0, 255,       120, 130, 140, 255,
    ]);

    test('Raw RGB conversion and reconstruction is 100% lossless', () {
      final converted = convertRgbaToBinary(
        rgbaBytes: sampleRgba,
        width: 3,
        height: 2,
        format: BinaryPixelFormat.rgb888,
        sourceFileName: 'sample.png',
        sourceColorMode: 'PNG • RGB (24-bit)',
      );

      expect(converted.totalBytes, 18);
      expect(converted.totalBits, 144);
      expect(converted.metadata.isLossless, isTrue);
      expect(converted.metadata.colorDepth, 24);
      expect(converted.metadata.channelOrder, 'RGB');

      // Simulate exporting metadata JSON + .bin bytes and re-importing them
      final exportedJson = converted.metadata.toJsonString();
      final importedMeta = ImageBinaryMetadata.fromJsonString(exportedJson);
      final importedBin = Uint8List.fromList(converted.binaryBytes);

      final reconstructed = reconstructBinaryToRgba(
        binaryData: importedBin,
        metadata: importedMeta,
      );

      expect(reconstructed, equals(sampleRgba));
      final metrics = compareRgbaBuffers(sampleRgba, reconstructed, 3, 2);
      expect(metrics.isExactRgbMatch, isTrue);
      expect(metrics.differingRgbPixels, 0);
      expect(metrics.maxChannelDiff, 0);
    });

    test('Grayscale conversion is marked lossy and produces 8-bit luminance bytes', () {
      final converted = convertRgbaToBinary(
        rgbaBytes: sampleRgba,
        width: 3,
        height: 2,
        format: BinaryPixelFormat.gray8,
        sourceFileName: 'sample.jpg',
        sourceColorMode: 'JPEG • YCbCr',
      );

      expect(converted.totalBytes, 6);
      expect(converted.totalBits, 48);
      expect(converted.metadata.isLossless, isFalse);
      expect(converted.metadata.colorDepth, 8);
      expect(converted.metadata.channelOrder, 'L');

      final reconstructed = reconstructBinaryToRgba(
        binaryData: converted.binaryBytes,
        metadata: converted.metadata,
      );

      // Reconstructed pixels are grayscale (R == G == B)
      for (int p = 0; p < 6; p++) {
        expect(reconstructed[p * 4], reconstructed[p * 4 + 1]);
        expect(reconstructed[p * 4 + 1], reconstructed[p * 4 + 2]);
      }

      final metrics = compareRgbaBuffers(sampleRgba, reconstructed, 3, 2);
      expect(metrics.isExactRgbMatch, isFalse);
    });

    test('1-bit monochrome conversion respects threshold, MSB packing, and lossy flag', () {
      // 9 pixels (3x3) -> 9 bits packed into 2 bytes (paddingBits = 7)
      final rgba3x3 = Uint8List.fromList([
        30, 30, 30, 255,    100, 100, 100, 255, 200, 200, 200, 255,
        50, 50, 50, 255,    128, 128, 128, 255, 240, 240, 240, 255,
        0, 0, 0, 255,       180, 180, 180, 255, 255, 255, 255, 255,
      ]);

      final lowThresh = convertRgbaToBinary(
        rgbaBytes: rgba3x3,
        width: 3,
        height: 3,
        format: BinaryPixelFormat.mono1,
        threshold: 80,
      );
      expect(lowThresh.totalBits, 9);
      expect(lowThresh.totalBytes, 2);
      expect(lowThresh.metadata.paddingBits, 7);
      expect(lowThresh.metadata.threshold, 80);
      expect(lowThresh.metadata.isLossless, isFalse);

      final highThresh = convertRgbaToBinary(
        rgbaBytes: rgba3x3,
        width: 3,
        height: 3,
        format: BinaryPixelFormat.mono1,
        threshold: 190,
      );
      expect(highThresh.binaryBytes, isNot(equals(lowThresh.binaryBytes)));

      final reconstructed = reconstructBinaryToRgba(
        binaryData: lowThresh.binaryBytes,
        metadata: lowThresh.metadata,
      );
      expect(reconstructed.length, 36);
      // Pixel 0 (lum ~30 < 80) -> black (0); Pixel 1 (lum ~100 >= 80) -> white (255)
      expect(reconstructed[0], 0);
      expect(reconstructed[4], 255);
      // Pixel 8 (lum 255 >= 80) -> white (255)
      expect(reconstructed[32], 255);
    });

    test('Rejects mismatched .bin length or corrupted CRC-32 metadata', () {
      final converted = convertRgbaToBinary(
        rgbaBytes: sampleRgba,
        width: 3,
        height: 2,
        format: BinaryPixelFormat.rgb888,
      );

      // Truncated .bin
      expect(
        () => reconstructBinaryToRgba(
          binaryData: converted.binaryBytes.sublist(0, 10),
          metadata: converted.metadata,
        ),
        throwsFormatException,
      );

      // Corrupted byte with valid length fails CRC-32 check
      final tampered = Uint8List.fromList(converted.binaryBytes);
      tampered[0] ^= 0xFF;
      expect(
        () => reconstructBinaryToRgba(
          binaryData: tampered,
          metadata: converted.metadata,
        ),
        throwsFormatException,
      );
    });

    test('Paginated binary preview and .txt streaming stay bounded', () {
      final buffer = Uint8List.fromList(List<int>.generate(150, (i) => i & 0xFF));
      final page0 = formatBinaryPage(buffer, pageIndex: 0, bytesPerPage: 64, bytesPerRow: 4);
      final page2 = formatBinaryPage(buffer, pageIndex: 2, bytesPerPage: 64, bytesPerRow: 4);

      expect(page0.totalPages, 3);
      expect(page0.startByte, 0);
      expect(page0.endByte, 64);
      expect(page0.rows.length, 16);
      expect(page2.startByte, 128);
      expect(page2.endByte, 150);

      final meta = ImageBinaryMetadata(
        width: 10,
        height: 15,
        pixelFormat: BinaryPixelFormat.gray8,
        colorDepth: 8,
        bitDepthPerChannel: 8,
        channelOrder: 'L',
        pixelCount: 150,
        totalBytes: 150,
        totalBits: 1200,
        paddingBits: 0,
        isLossless: false,
        sourceFileName: 'test.png',
        sourceColorMode: 'Grayscale',
        crc32: computeCrc32(buffer),
        createdAt: '2026-11-22T00:00:00Z',
      );
      final chunks = streamTxtChunks(buffer, meta, bytesPerLine: 8, chunkLineCount: 8).toList();
      expect(chunks.length, greaterThan(1));
      final fullTxt = utf8.decode(chunks.expand((c) => c).toList());
      expect(fullTxt, contains('width=10 height=15 format=gray8'));
    });
  });

  group('ImageToBinaryScreen Arabic RTL Widget Tests', () {
    testWidgets('Renders Arabic RTL interface and enforces metadata requirement on reconstruction',
        (WidgetTester tester) async {
      await tester.pumpWidget(_createTestApp(const ImageToBinaryScreen()));
      await tester.pumpAndSettle();

      // Verify RTL directionality
      final dir = tester.widget<Directionality>(find.byType(Directionality).first);
      expect(dir.textDirection, TextDirection.rtl);

      // Verify main Arabic header and workflow steps
      expect(find.text('تحويل الصورة إلى ثنائي'), findsOneWidget);
      expect(find.text('اختيار صورة من الجهاز'), findsOneWidget);

      // Switch to 1-bit monochrome mode and confirm threshold slider appears
      final monoFinder = find.text('أبيض وأسود (1 بت)');
      await tester.ensureVisible(monoFinder);
      await tester.tap(monoFinder);
      await tester.pumpAndSettle();
      expect(find.text('عتبة الأبيض والأسود:'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      // Switch to reconstruction tab and verify it guards against missing .bin / metadata
      final reconTabFinder = find.text('ثنائي ← صورة');
      await tester.ensureVisible(reconTabFinder);
      await tester.tap(reconTabFinder);
      await tester.pumpAndSettle();
      final reconBtnFinder = find.text('إعادة بناء الصورة');
      await tester.ensureVisible(reconBtnFinder);
      await tester.tap(reconBtnFinder);
      await tester.pumpAndSettle();
      expect(find.textContaining('يرجى اختيار ملف البيانات الثنائية (.bin)'), findsOneWidget);
    });

    testWidgets('HomeScreen provides direct navigation entry to ImageToBinaryScreen',
        (WidgetTester tester) async {
      const safChannel = MethodChannel('com.magickey/saf');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(safChannel, (MethodCall call) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(safChannel, null);
      });

      await tester.pumpWidget(
        _createTestApp(
          HomeScreen(
            onToggleTheme: () {},
            onLocaleChange: (_) {},
            currentLocale: const Locale('en'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final entryFinder = find.text('Image to Binary');
      expect(entryFinder, findsOneWidget);
      await tester.ensureVisible(entryFinder);
      await tester.tap(entryFinder);
      await tester.pumpAndSettle();

      expect(find.byType(ImageToBinaryScreen), findsOneWidget);
      expect(find.text('تحويل الصورة إلى ثنائي'), findsOneWidget);
    });

    testWidgets('Actual sample.png image RGB conversion and lossless pixel reconstruction produces 0 differences',
        (WidgetTester tester) async {
      final sampleFile = File('../manual_test_files/sample.png');
      if (!sampleFile.existsSync()) {
        return;
      }

      late DecodedImageInfo decoded;
      late Uint8List reDecodedRgba;
      late ImageBinaryConversionResult converted;

      await tester.runAsync(() async {
        final fileBytes = await sampleFile.readAsBytes();
        decoded = await decodeImageBytesToRgba(
          fileBytes: fileBytes,
          fileName: 'sample.png',
          fileSizeBytes: fileBytes.length,
        );

        converted = convertRgbaToBinary(
          rgbaBytes: decoded.rgbaBytes,
          width: decoded.width,
          height: decoded.height,
          format: BinaryPixelFormat.rgb888,
          sourceFileName: decoded.fileName,
          sourceColorMode: '${decoded.detectedFormat} • ${decoded.colorMode}',
          sourceHadAlpha: decoded.hasTransparentPixels,
        );

        final importedMeta = ImageBinaryMetadata.fromJsonString(converted.metadata.toJsonString());
        final reconstructedRgba = reconstructBinaryToRgba(
          binaryData: converted.binaryBytes,
          metadata: importedMeta,
        );
        final reconstructedPng = await encodeRgbaToPngBytes(
          rgbaBytes: reconstructedRgba,
          width: importedMeta.width,
          height: importedMeta.height,
        );
        final reDecoded = await decodeImageBytesToRgba(
          fileBytes: reconstructedPng,
          fileName: 'reconstructed.png',
          fileSizeBytes: reconstructedPng.length,
        );
        reDecodedRgba = reDecoded.rgbaBytes;
      });

      final metrics = compareRgbaBuffers(
        decoded.rgbaBytes,
        reDecodedRgba,
        decoded.width,
        decoded.height,
      );
      expect(decoded.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
      expect(metrics.isExactRgbMatch, isTrue);
      expect(metrics.differingRgbPixels, 0);
      expect(metrics.maxChannelDiff, 0);
    });

    testWidgets('End-to-end SAF workflow: select PNG, convert RGB, export .bin/.meta.json, re-import & verify lossless match',
        (WidgetTester tester) async {
      const safChannel = MethodChannel('com.magickey/saf');
      // Valid 1x1 red opaque PNG
      final redPixelPng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0xC9, 0xFE, 0x92,
        0xEF, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      final Map<String, List<int>> writtenStreams = {};
      String openMode = 'image';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(safChannel, (MethodCall call) async {
        switch (call.method) {
          case 'openDocument':
            if (openMode == 'image') {
              return {
                'uri': 'content://test/red.png',
                'name': 'red.png',
                'size': redPixelPng.length,
              };
            } else if (openMode == 'bin') {
              final bytes = writtenStreams['content://export/out.bin'] ?? <int>[];
              return {
                'uri': 'content://export/out.bin',
                'name': 'out.bin',
                'size': bytes.length,
              };
            } else {
              final bytes = writtenStreams['content://export/out.meta.json'] ?? <int>[];
              return {
                'uri': 'content://export/out.meta.json',
                'name': 'out.meta.json',
                'size': bytes.length,
              };
            }
          case 'readUriChunk':
            final args = call.arguments as Map;
            final uri = args['uri'] as String;
            final offset = (args['offset'] as num).toInt();
            final length = (args['length'] as num).toInt();
            final Uint8List source = uri == 'content://test/red.png'
                ? redPixelPng
                : Uint8List.fromList(writtenStreams[uri] ?? <int>[]);
            if (offset >= source.length) return Uint8List(0);
            final end = (offset + length < source.length) ? offset + length : source.length;
            return Uint8List.sublistView(source, offset, end);
          case 'createDocument':
            final args = call.arguments as Map;
            final fileName = args['fileName'] as String;
            return fileName.endsWith('.bin')
                ? 'content://export/out.bin'
                : 'content://export/out.meta.json';
          case 'openUriWriteSession':
            final args = call.arguments as Map;
            final uri = args['uri'] as String;
            writtenStreams[uri] = <int>[];
            return uri;
          case 'writeUriSessionChunk':
            final args = call.arguments as Map;
            final sessionId = args['sessionId'] as String;
            final bytes = args['bytes'] as Uint8List;
            writtenStreams[sessionId]?.addAll(bytes);
            return true;
          case 'closeUriWriteSession':
            return true;
          default:
            return null;
        }
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(safChannel, null);
      });

      await tester.pumpWidget(_createTestApp(const ImageToBinaryScreen()));
      await tester.pumpAndSettle();

      Future<void> waitForFinder(Finder target) async {
        for (int i = 0; i < 60; i++) {
          if (target.evaluate().isNotEmpty) return;
          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 25)));
          await tester.pump();
        }
      }

      await tester.tap(find.text('اختيار صورة من الجهاز'));
      await tester.pump();
      await waitForFinder(find.textContaining('1 × 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 × 1'), findsOneWidget);

      final convertBtn = find.text('تحويل إلى بيانات ثنائية');
      await tester.ensureVisible(convertBtn);
      await tester.tap(convertBtn);
      await tester.pumpAndSettle();
      expect(find.text('24'), findsOneWidget); // 24 bits

      // Export .bin and .meta.json
      final exportBinBtn = find.textContaining('تصدير البيانات الفعلية (.bin');
      await tester.ensureVisible(exportBinBtn);
      await tester.tap(exportBinBtn);
      await tester.pumpAndSettle();

      final exportMetaBtn = find.textContaining('تصدير البيانات الوصفية المطلوبة');
      await tester.ensureVisible(exportMetaBtn);
      await tester.tap(exportMetaBtn);
      await tester.pumpAndSettle();

      expect(writtenStreams['content://export/out.bin'], equals([255, 0, 0]));
      expect(writtenStreams['content://export/out.meta.json'], isNotEmpty);

      // Re-import exported .bin and .meta.json on reconstruction tab
      final reconTab = find.text('ثنائي ← صورة');
      await tester.ensureVisible(reconTab);
      await tester.tap(reconTab);
      await tester.pumpAndSettle();

      openMode = 'bin';
      final pickBinBtn = find.text('اختيار ملف .bin');
      await tester.ensureVisible(pickBinBtn);
      await tester.tap(pickBinBtn);
      await tester.pumpAndSettle();

      openMode = 'meta';
      final pickMetaBtn = find.text('اختيار ملف البيانات الوصفية (.meta.json)');
      await tester.ensureVisible(pickMetaBtn);
      await tester.tap(pickMetaBtn);
      await tester.pumpAndSettle();

      final reconBtn = find.text('إعادة بناء الصورة');
      await tester.ensureVisible(reconBtn);
      await tester.tap(reconBtn);
      await tester.pump();
      await waitForFinder(find.textContaining('تطابق تام 100%'));
      await tester.pumpAndSettle();

      expect(find.textContaining('تطابق تام 100%'), findsOneWidget);
    });
  });
}
