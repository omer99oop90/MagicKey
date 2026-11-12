import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magickey/models/file_source.dart';
import 'package:magickey/services/file_service.dart';
import 'package:magickey/services/recent_files_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('com.magickey/saf');

  group('RecentFilesService Tests', () {
    final recentService = RecentFilesService.instance;

    setUp(() {
      recentService.clear();
    });

    test('Add single file to recents', () {
      final source = AndroidUriFileSource(uri: 'content://test/file1', name: 'file1.txt', size: 100);
      recentService.add(source);

      expect(recentService.entries.length, 1);
      expect(recentService.entries.first.name, 'file1.txt');
      expect(recentService.entries.first.uri, 'content://test/file1');
      expect(recentService.entries.first.size, 100);
    });

    test('Re-adding existing file moves it to the top (deduplication & MRU)', () {
      final source1 = AndroidUriFileSource(uri: 'content://test/file1', name: 'file1.txt', size: 100);
      final source2 = AndroidUriFileSource(uri: 'content://test/file2', name: 'file2.txt', size: 200);

      recentService.add(source1);
      recentService.add(source2);

      expect(recentService.entries.length, 2);
      expect(recentService.entries.first.name, 'file2.txt');

      // Re-add file1
      recentService.add(source1);

      expect(recentService.entries.length, 2);
      expect(recentService.entries.first.name, 'file1.txt');
      expect(recentService.entries.last.name, 'file2.txt');
    });

    test('Strict enforcement of 10-entry maximum cap', () {
      for (int i = 1; i <= 15; i++) {
        final source = AndroidUriFileSource(
          uri: 'content://test/file_$i',
          name: 'file_$i.txt',
          size: i * 100,
        );
        recentService.add(source);
      }

      // Assert capped at 10
      expect(recentService.entries.length, 10);
      // Newest file (15) must be at index 0
      expect(recentService.entries.first.name, 'file_15.txt');
      // Oldest retained file (6) must be at index 9 (files 1..5 were dropped)
      expect(recentService.entries.last.name, 'file_6.txt');
    });

    test('Clear history empties entries list', () {
      final source = AndroidUriFileSource(uri: 'content://test/file1', name: 'file1.txt', size: 100);
      recentService.add(source);
      expect(recentService.entries.isNotEmpty, isTrue);

      recentService.clear();
      expect(recentService.entries.isEmpty, isTrue);
    });

    test('RecentFileEntry toSource correctly reconstructs FileSource', () {
      final entryUri = RecentFileEntry(
        name: 'doc.pdf',
        uri: 'content://test/doc.pdf',
        size: 5000,
        openedAt: DateTime.now(),
      );
      final sourceUri = entryUri.toSource();
      expect(sourceUri, isA<AndroidUriFileSource>());
      expect(sourceUri.name, 'doc.pdf');
      expect(sourceUri.uri, 'content://test/doc.pdf');

      final entryPath = RecentFileEntry(
        name: 'local.txt',
        path: '/storage/local.txt',
        size: 200,
        openedAt: DateTime.now(),
      );
      final sourcePath = entryPath.toSource();
      expect(sourcePath, isA<LocalPathFileSource>());
      expect(sourcePath.name, 'local.txt');
      expect(sourcePath.path, '/storage/local.txt');
    });
  });

  group('Incoming Intent Delivery & Deduplication Tests', () {
    String? mockInitialUri;
    Map<String, dynamic>? mockMetadata;

    setUp(() {
      mockInitialUri = null;
      mockMetadata = {
        'name': 'shared_doc.txt',
        'size': 4096,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'getInitialIntentUri') {
            final uri = mockInitialUri;
            mockInitialUri = null; // consume
            return uri;
          }
          if (call.method == 'getMetadata') {
            final args = call.arguments as Map?;
            final uriStr = args?['uri'] as String?;
            return {
              'uri': uriStr,
              'name': mockMetadata?['name'] ?? 'file',
              'size': mockMetadata?['size'] ?? 100,
            };
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('Cold Start: checkInitialIntent retrieves URI and resolves FileSource', () async {
      mockInitialUri = 'content://com.magickey/cold_start_file.pdf';
      mockMetadata = {'name': 'cold_start_file.pdf', 'size': 8192};

      final fileService = FileService.instance;
      final fileSource = await fileService.checkInitialIntent();

      expect(fileSource, isNotNull);
      expect(fileSource!.name, 'cold_start_file.pdf');
      expect(fileSource.size, 8192);
      expect(fileSource.uri, 'content://com.magickey/cold_start_file.pdf');

      // Second check should return null because initial intent was consumed
      final secondCheck = await fileService.checkInitialIntent();
      expect(secondCheck, isNull);
    });

    test('Cold Start with null or empty intent returns null safely', () async {
      mockInitialUri = null;
      final fileService = FileService.instance;
      final fileSource = await fileService.checkInitialIntent();
      expect(fileSource, isNull);
    });

    test('Warm Start: onNewIntentUri delivers incoming file via onIncomingFile stream', () async {
      final fileService = FileService.instance;
      mockMetadata = {'name': 'warm_shared_image.png', 'size': 65536};

      const sharedUri = 'content://com.whatsapp.provider/warm_shared_image.png';

      final completer = Completer<FileSource>();
      final sub = fileService.onIncomingFile.listen((source) {
        if (!completer.isCompleted) {
          completer.complete(source);
        }
      });

      // Simulate native calling onNewIntentUri into Dart
      final ByteData? message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNewIntentUri', sharedUri),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'com.magickey/saf',
        message,
        (ByteData? reply) {},
      );

      final deliveredSource = await completer.future.timeout(const Duration(seconds: 2));
      expect(deliveredSource.name, 'warm_shared_image.png');
      expect(deliveredSource.size, 65536);
      expect(deliveredSource.uri, sharedUri);

      await sub.cancel();
    });

    test('Deduplication: rapid duplicate intent for same URI is dropped', () async {
      final fileService = FileService.instance;
      mockMetadata = {'name': 'dedup.png', 'size': 100};
      const duplicateUri = 'content://com.example/dedup_unique_test.png';

      int deliveryCount = 0;
      final sub = fileService.onIncomingFile.listen((source) {
        if (source.uri == duplicateUri) {
          deliveryCount++;
        }
      });

      final ByteData? message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNewIntentUri', duplicateUri),
      );

      // Trigger twice immediately
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'com.magickey/saf',
        message,
        (ByteData? reply) {},
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'com.magickey/saf',
        message,
        (ByteData? reply) {},
      );

      // Allow event loop to process
      await Future.delayed(const Duration(milliseconds: 50));

      expect(deliveryCount, 1);
      await sub.cancel();
    });
  });

  group('SAF File Picker & Cancellation Path Tests', () {
    final fileService = FileService.instance;

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('Cancellation: openDocument returning null yields null without throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'openDocument') {
            return null; // System picker canceled
          }
          return null;
        },
      );

      final result = await fileService.pickFile();
      expect(result, isNull);
    });

    test('Cancellation: openDocument returning missing or null URI yields null safely', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'openDocument') {
            return {'name': 'partial.txt', 'size': 50}; // missing 'uri'
          }
          return null;
        },
      );

      final result = await fileService.pickFile();
      expect(result, isNull);
    });

    test('Error containment: PlatformException from SAF bridge returns null without unhandled error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'openDocument') {
            throw PlatformException(code: 'CANCELED', message: 'Activity canceled');
          }
          return null;
        },
      );

      final result = await fileService.pickFile();
      expect(result, isNull);
    });

    test('Successful selection: openDocument returning valid map yields AndroidUriFileSource', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'openDocument') {
            return {
              'uri': 'content://com.android.providers.media/documents/document/image%3A1024',
              'name': 'vacation.jpg',
              'size': 204800,
            };
          }
          return null;
        },
      );

      final result = await fileService.pickFile(mimeType: 'image/*');
      expect(result, isNotNull);
      expect(result, isA<AndroidUriFileSource>());
      expect(result!.name, 'vacation.jpg');
      expect(result.size, 204800);
      expect(result.uri, 'content://com.android.providers.media/documents/document/image%3A1024');
    });

    test('Sequential repeated launches: multiple cancellations and selections succeed without session lock', () async {
      int launchCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'openDocument') {
            launchCount++;
            if (launchCount == 1) return null; // Cancel
            if (launchCount == 2) {
              return {'uri': 'content://test/file2', 'name': 'file2.txt', 'size': 100};
            }
            return null; // Cancel again
          }
          return null;
        },
      );

      // Launch 1: Canceled
      final res1 = await fileService.pickFile();
      expect(res1, isNull);

      // Launch 2: Selected
      final res2 = await fileService.pickFile();
      expect(res2, isNotNull);
      expect(res2!.name, 'file2.txt');

      // Launch 3: Canceled
      final res3 = await fileService.pickFile();
      expect(res3, isNull);

      expect(launchCount, 3);
    });
  });
}
