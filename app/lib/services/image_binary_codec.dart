import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/file_source.dart';

/// Supported pixel encoding modes for Image-to-Binary conversion and reconstruction.
enum BinaryPixelFormat {
  rgb888,
  gray8,
  mono1,
}

extension BinaryPixelFormatMeta on BinaryPixelFormat {
  String get id {
    switch (this) {
      case BinaryPixelFormat.rgb888:
        return 'rgb888';
      case BinaryPixelFormat.gray8:
        return 'gray8';
      case BinaryPixelFormat.mono1:
        return 'mono1';
    }
  }

  int get colorDepth {
    switch (this) {
      case BinaryPixelFormat.rgb888:
        return 24;
      case BinaryPixelFormat.gray8:
        return 8;
      case BinaryPixelFormat.mono1:
        return 1;
    }
  }

  int get bitDepthPerChannel {
    switch (this) {
      case BinaryPixelFormat.rgb888:
        return 8;
      case BinaryPixelFormat.gray8:
        return 8;
      case BinaryPixelFormat.mono1:
        return 1;
    }
  }

  String get channelOrder {
    switch (this) {
      case BinaryPixelFormat.rgb888:
        return 'RGB';
      case BinaryPixelFormat.gray8:
        return 'L';
      case BinaryPixelFormat.mono1:
        return 'MONO_MSB';
    }
  }

  bool get isLosslessRgb => this == BinaryPixelFormat.rgb888;

  String get arabicLabel {
    switch (this) {
      case BinaryPixelFormat.rgb888:
        return 'RGB خام (24 بت — بدون فقدان لقنوات RGB)';
      case BinaryPixelFormat.gray8:
        return 'تدرج رمادي (8 بت — تحويل فقداني)';
      case BinaryPixelFormat.mono1:
        return 'أحادي اللون (1 بت — تحويل فقداني)';
    }
  }

  String get arabicShortLabel {
    switch (this) {
      case BinaryPixelFormat.rgb888:
        return 'RGB خام (8 بت/قناة)';
      case BinaryPixelFormat.gray8:
        return 'تدرج رمادي (8 بت)';
      case BinaryPixelFormat.mono1:
        return 'أبيض وأسود (1 بت)';
    }
  }

  static BinaryPixelFormat fromId(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'rgb888':
      case 'rgb':
        return BinaryPixelFormat.rgb888;
      case 'gray8':
      case 'grayscale':
      case 'l':
        return BinaryPixelFormat.gray8;
      case 'mono1':
      case '1bit':
      case 'monochrome':
        return BinaryPixelFormat.mono1;
      default:
        throw FormatException('صيغة بكسل غير مدعومة في البيانات الوصفية: $raw');
    }
  }
}

/// Inspects container headers (PNG, JPEG, WEBP) to determine image format and color mode.
class ImageHeaderInfo {
  final String formatId;
  final String colorMode;
  final bool hasAlphaChannel;

  const ImageHeaderInfo({
    required this.formatId,
    required this.colorMode,
    required this.hasAlphaChannel,
  });

  static bool isSupportedExtension(String ext) {
    final lower = ext.toLowerCase().trim();
    return lower == 'png' || lower == 'jpg' || lower == 'jpeg' || lower == 'webp';
  }

  /// Inspects raw image file bytes for PNG, JPEG, or WEBP signatures and color mode metadata.
  static ImageHeaderInfo? inspect(Uint8List bytes) {
    if (bytes.length >= 26 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      // PNG IHDR starts at offset 8 (length 4, 'IHDR' 4, width 4, height 4, bitDepth 1, colorType 1)
      if (bytes[12] == 0x49 && bytes[13] == 0x48 && bytes[14] == 0x44 && bytes[15] == 0x52) {
        final bitDepth = bytes[24];
        final colorType = bytes[25];
        switch (colorType) {
          case 0:
            return ImageHeaderInfo(
              formatId: 'PNG',
              colorMode: 'Grayscale ($bitDepth-bit)',
              hasAlphaChannel: false,
            );
          case 2:
            return ImageHeaderInfo(
              formatId: 'PNG',
              colorMode: 'RGB (${bitDepth * 3}-bit)',
              hasAlphaChannel: false,
            );
          case 3:
            return ImageHeaderInfo(
              formatId: 'PNG',
              colorMode: 'Indexed Palette ($bitDepth-bit)',
              hasAlphaChannel: false,
            );
          case 4:
            return ImageHeaderInfo(
              formatId: 'PNG',
              colorMode: 'Grayscale + Alpha (${bitDepth * 2}-bit)',
              hasAlphaChannel: true,
            );
          case 6:
            return ImageHeaderInfo(
              formatId: 'PNG',
              colorMode: 'RGBA (${bitDepth * 4}-bit)',
              hasAlphaChannel: true,
            );
        }
      }
      return const ImageHeaderInfo(
        formatId: 'PNG',
        colorMode: 'RGB / RGBA',
        hasAlphaChannel: true,
      );
    }

    // JPEG magic: FF D8 FF
    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      int offset = 2;
      while (offset + 9 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        final marker = bytes[offset + 1];
        if (marker == 0xD8 || marker == 0xD9 || marker == 0x00 || (marker >= 0xD0 && marker <= 0xD7)) {
          offset += 2;
          continue;
        }
        final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
        if (segLen < 2) break;
        final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF);
        if (isSof && offset + 9 < bytes.length) {
          final precision = bytes[offset + 4];
          final components = bytes[offset + 9];
          if (components == 1) {
            return ImageHeaderInfo(
              formatId: 'JPEG',
              colorMode: 'Grayscale ($precision-bit)',
              hasAlphaChannel: false,
            );
          } else if (components == 3) {
            return ImageHeaderInfo(
              formatId: 'JPEG',
              colorMode: 'YCbCr / RGB (${precision * 3}-bit)',
              hasAlphaChannel: false,
            );
          } else if (components == 4) {
            return ImageHeaderInfo(
              formatId: 'JPEG',
              colorMode: 'CMYK / YCCK (${precision * 4}-bit)',
              hasAlphaChannel: false,
            );
          }
        }
        offset += 2 + segLen;
      }
      return const ImageHeaderInfo(
        formatId: 'JPEG',
        colorMode: 'YCbCr / RGB (24-bit)',
        hasAlphaChannel: false,
      );
    }

    // WEBP magic: RIFF....WEBP
    if (bytes.length >= 16 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      final chunk = String.fromCharCodes(bytes.sublist(12, 16));
      if (chunk == 'VP8L') {
        return const ImageHeaderInfo(
          formatId: 'WEBP',
          colorMode: 'RGBA Lossless (32-bit)',
          hasAlphaChannel: true,
        );
      } else if (chunk == 'VP8X' && bytes.length >= 21) {
        final hasAlpha = (bytes[20] & 0x10) != 0;
        return ImageHeaderInfo(
          formatId: 'WEBP',
          colorMode: hasAlpha ? 'RGBA Extended (32-bit)' : 'RGB Extended (24-bit)',
          hasAlphaChannel: hasAlpha,
        );
      }
      return const ImageHeaderInfo(
        formatId: 'WEBP',
        colorMode: 'YUV / RGB (24-bit)',
        hasAlphaChannel: false,
      );
    }

    return null;
  }
}

/// Decoded RGBA image payload ready for local pixel conversion.
class DecodedImageInfo {
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final String fileName;
  final int fileSizeBytes;
  final String detectedFormat;
  final String colorMode;
  final bool hasTransparentPixels;

  const DecodedImageInfo({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.fileName,
    required this.fileSizeBytes,
    required this.detectedFormat,
    required this.colorMode,
    required this.hasTransparentPixels,
  });

  int get pixelCount => width * height;
}

/// Complete metadata required to faithfully reconstruct an image from raw .bin bytes.
class ImageBinaryMetadata {
  static const String currentSignature = 'MAGICKEY_IMAGE_BINARY';
  static const int currentSchemaVersion = 1;

  final String formatSignature;
  final int schemaVersion;
  final int width;
  final int height;
  final BinaryPixelFormat pixelFormat;
  final int colorDepth;
  final int bitDepthPerChannel;
  final String channelOrder;
  final String bitOrder;
  final int pixelCount;
  final int totalBytes;
  final int totalBits;
  final int paddingBits;
  final int? threshold;
  final bool isLossless;
  final bool sourceHadAlpha;
  final String sourceFileName;
  final String sourceColorMode;
  final int crc32;
  final String createdAt;

  const ImageBinaryMetadata({
    this.formatSignature = currentSignature,
    this.schemaVersion = currentSchemaVersion,
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.colorDepth,
    required this.bitDepthPerChannel,
    required this.channelOrder,
    this.bitOrder = 'MSB_FIRST',
    required this.pixelCount,
    required this.totalBytes,
    required this.totalBits,
    required this.paddingBits,
    this.threshold,
    required this.isLossless,
    this.sourceHadAlpha = false,
    required this.sourceFileName,
    required this.sourceColorMode,
    required this.crc32,
    required this.createdAt,
  });

  int get expectedByteLength {
    final pixels = width * height;
    switch (pixelFormat) {
      case BinaryPixelFormat.rgb888:
        return pixels * 3;
      case BinaryPixelFormat.gray8:
        return pixels;
      case BinaryPixelFormat.mono1:
        return (pixels + 7) >> 3;
    }
  }

  String get crc32Hex => crc32.toRadixString(16).toUpperCase().padLeft(8, '0');

  /// Validates that [payload] matches the expected dimensions, format byte length, and CRC-32 checksum.
  void validateBinaryPayload(Uint8List payload) {
    if (width <= 0 || height <= 0) {
      throw const FormatException('أبعاد الصورة في البيانات الوصفية غير صالحة.');
    }
    final expected = expectedByteLength;
    if (payload.length != expected) {
      throw FormatException(
        'حجم ملف .bin (${payload.length} بايت) لا يطابق الحجم المتوقع ($expected بايت) للأبعاد $width×$height وصيغة ${pixelFormat.id}.',
      );
    }
    final actualCrc = computeCrc32(payload);
    if (crc32 != 0 && actualCrc != crc32) {
      throw FormatException(
        'فشل التحقق من سلامة البيانات (CRC-32): المتوقع $crc32Hex، الفعلي ${actualCrc.toRadixString(16).toUpperCase().padLeft(8, '0')}. قد يكون ملف .bin غير مطابق لملف البيانات الوصفية.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
        'format_signature': formatSignature,
        'schema_version': schemaVersion,
        'width': width,
        'height': height,
        'pixel_format': pixelFormat.id,
        'color_depth': colorDepth,
        'bit_depth_per_channel': bitDepthPerChannel,
        'channel_order': channelOrder,
        'bit_order': bitOrder,
        'pixel_count': pixelCount,
        'total_bytes': totalBytes,
        'total_bits': totalBits,
        'padding_bits': paddingBits,
        'threshold': threshold,
        'is_lossless': isLossless,
        'source_had_alpha': sourceHadAlpha,
        'source_file_name': sourceFileName,
        'source_color_mode': sourceColorMode,
        'crc32': crc32,
        'crc32_hex': crc32Hex,
        'created_at': createdAt,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ImageBinaryMetadata.fromJson(Map<String, dynamic> json) {
    final sig = json['format_signature'] as String?;
    if (sig != null && sig != currentSignature) {
      throw FormatException('توقيع البيانات الوصفية غير معروف: $sig');
    }

    final width = (json['width'] as num?)?.toInt() ?? 0;
    final height = (json['height'] as num?)?.toInt() ?? 0;
    if (width <= 0 || height <= 0) {
      throw const FormatException('يجب أن يحتوي ملف البيانات الوصفية على width و height أكبر من 0.');
    }

    final pixelFormat = BinaryPixelFormatMeta.fromId(json['pixel_format'] as String?);
    final pixelCount = (json['pixel_count'] as num?)?.toInt() ?? (width * height);
    final expectedTotalBytes = switch (pixelFormat) {
      BinaryPixelFormat.rgb888 => width * height * 3,
      BinaryPixelFormat.gray8 => width * height,
      BinaryPixelFormat.mono1 => (width * height + 7) >> 3,
    };
    final expectedTotalBits = switch (pixelFormat) {
      BinaryPixelFormat.rgb888 => width * height * 24,
      BinaryPixelFormat.gray8 => width * height * 8,
      BinaryPixelFormat.mono1 => width * height,
    };

    return ImageBinaryMetadata(
      formatSignature: sig ?? currentSignature,
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      width: width,
      height: height,
      pixelFormat: pixelFormat,
      colorDepth: (json['color_depth'] as num?)?.toInt() ?? pixelFormat.colorDepth,
      bitDepthPerChannel:
          (json['bit_depth_per_channel'] as num?)?.toInt() ?? pixelFormat.bitDepthPerChannel,
      channelOrder: (json['channel_order'] as String?) ?? pixelFormat.channelOrder,
      bitOrder: (json['bit_order'] as String?) ?? 'MSB_FIRST',
      pixelCount: pixelCount,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? expectedTotalBytes,
      totalBits: (json['total_bits'] as num?)?.toInt() ?? expectedTotalBits,
      paddingBits: (json['padding_bits'] as num?)?.toInt() ??
          (pixelFormat == BinaryPixelFormat.mono1 ? (8 - (expectedTotalBits % 8)) % 8 : 0),
      threshold: (json['threshold'] as num?)?.toInt(),
      isLossless: json['is_lossless'] as bool? ?? pixelFormat.isLosslessRgb,
      sourceHadAlpha: json['source_had_alpha'] as bool? ?? false,
      sourceFileName: (json['source_file_name'] as String?) ?? 'unknown',
      sourceColorMode: (json['source_color_mode'] as String?) ?? 'Unknown',
      crc32: (json['crc32'] as num?)?.toInt() ?? 0,
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }

  static ImageBinaryMetadata fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ملف البيانات الوصفية JSON غير صالح.');
    }
    return ImageBinaryMetadata.fromJson(decoded);
  }
}

/// Output produced by converting an image's pixels to a compact byte buffer + metadata.
class ImageBinaryConversionResult {
  final Uint8List binaryBytes;
  final ImageBinaryMetadata metadata;

  const ImageBinaryConversionResult({
    required this.binaryBytes,
    required this.metadata,
  });

  int get totalBytes => metadata.totalBytes;
  int get totalBits => metadata.totalBits;
}

/// One formatted row inside the paginated binary preview (up to [bytesPerRow] bytes).
class BinaryPreviewRow {
  final int byteOffset;
  final int byteCount;
  final String offsetHex;
  final String bitsText;

  const BinaryPreviewRow({
    required this.byteOffset,
    required this.byteCount,
    required this.offsetHex,
    required this.bitsText,
  });

  String get formattedLine => '$offsetHex  $bitsText';
}

/// Bounded single-page view over a binary buffer so giant strings are never created in UI memory.
class BinaryPreviewPage {
  final int pageIndex;
  final int totalPages;
  final int startByte;
  final int endByte;
  final List<BinaryPreviewRow> rows;

  const BinaryPreviewPage({
    required this.pageIndex,
    required this.totalPages,
    required this.startByte,
    required this.endByte,
    required this.rows,
  });
}

/// Quantitative comparison between an original RGBA buffer and a reconstructed RGBA buffer.
class PixelComparisonMetrics {
  final int pixelCount;
  final int identicalRgbPixels;
  final int differingRgbPixels;
  final int maxChannelDiff;
  final double meanAbsoluteChannelError;

  const PixelComparisonMetrics({
    required this.pixelCount,
    required this.identicalRgbPixels,
    required this.differingRgbPixels,
    required this.maxChannelDiff,
    required this.meanAbsoluteChannelError,
  });

  bool get isExactRgbMatch => differingRgbPixels == 0 && maxChannelDiff == 0;
  double get exactMatchPercent =>
      pixelCount > 0 ? (identicalRgbPixels / pixelCount) * 100.0 : 0.0;
}

/// Precomputed 256-entry lookup table mapping any byte [0..255] to its 8-bit MSB-first string.
final List<String> _kByteToBitsTable = List<String>.unmodifiable(
  List<String>.generate(
    256,
    (value) => value.toRadixString(2).padLeft(8, '0'),
  ),
);

/// Standard IEEE 802.3 CRC-32 table.
final List<int> _kCrc32Table = List<int>.unmodifiable(
  List<int>.generate(256, (i) {
    int c = i;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    return c;
  }),
);

/// Computes IEEE 802.3 CRC-32 checksum over [bytes].
int computeCrc32(Uint8List bytes) {
  int crc = 0xFFFFFFFF;
  for (int i = 0; i < bytes.length; i++) {
    crc = _kCrc32Table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Checks if an RGBA8888 buffer contains any non-opaque pixel (`alpha < 255`).
bool detectAlphaInRgba(Uint8List rgbaBytes) {
  for (int i = 3; i < rgbaBytes.length; i += 4) {
    if (rgbaBytes[i] < 255) return true;
  }
  return false;
}

/// Converts straight RGBA8888 pixel bytes into [format] binary bytes + metadata.
ImageBinaryConversionResult convertRgbaToBinary({
  required Uint8List rgbaBytes,
  required int width,
  required int height,
  required BinaryPixelFormat format,
  int threshold = 128,
  String sourceFileName = 'image',
  String sourceColorMode = 'RGB',
  bool sourceHadAlpha = false,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Image width and height must be positive.');
  }
  final pixelCount = width * height;
  if (rgbaBytes.length < pixelCount * 4) {
    throw ArgumentError(
      'RGBA buffer too small: expected ${pixelCount * 4} bytes, got ${rgbaBytes.length}.',
    );
  }

  final clampedThreshold = threshold.clamp(0, 255);
  late final Uint8List output;
  late final int totalBits;
  late final int paddingBits;

  switch (format) {
    case BinaryPixelFormat.rgb888:
      output = Uint8List(pixelCount * 3);
      for (int p = 0, src = 0, dst = 0; p < pixelCount; p++, src += 4, dst += 3) {
        output[dst] = rgbaBytes[src];
        output[dst + 1] = rgbaBytes[src + 1];
        output[dst + 2] = rgbaBytes[src + 2];
      }
      totalBits = pixelCount * 24;
      paddingBits = 0;
      break;

    case BinaryPixelFormat.gray8:
      output = Uint8List(pixelCount);
      for (int p = 0, src = 0; p < pixelCount; p++, src += 4) {
        final r = rgbaBytes[src];
        final g = rgbaBytes[src + 1];
        final b = rgbaBytes[src + 2];
        output[p] = ((77 * r + 150 * g + 29 * b + 128) >> 8).clamp(0, 255);
      }
      totalBits = pixelCount * 8;
      paddingBits = 0;
      break;

    case BinaryPixelFormat.mono1:
      final byteCount = (pixelCount + 7) >> 3;
      output = Uint8List(byteCount);
      for (int p = 0, src = 0; p < pixelCount; p++, src += 4) {
        final r = rgbaBytes[src];
        final g = rgbaBytes[src + 1];
        final b = rgbaBytes[src + 2];
        final lum = (77 * r + 150 * g + 29 * b + 128) >> 8;
        if (lum >= clampedThreshold) {
          output[p >> 3] |= 1 << (7 - (p & 7));
        }
      }
      totalBits = pixelCount;
      paddingBits = (8 - (pixelCount % 8)) % 8;
      break;
  }

  final crc = computeCrc32(output);
  final metadata = ImageBinaryMetadata(
    width: width,
    height: height,
    pixelFormat: format,
    colorDepth: format.colorDepth,
    bitDepthPerChannel: format.bitDepthPerChannel,
    channelOrder: format.channelOrder,
    bitOrder: 'MSB_FIRST',
    pixelCount: pixelCount,
    totalBytes: output.length,
    totalBits: totalBits,
    paddingBits: paddingBits,
    threshold: format == BinaryPixelFormat.mono1 ? clampedThreshold : null,
    isLossless: format.isLosslessRgb,
    sourceHadAlpha: sourceHadAlpha,
    sourceFileName: sourceFileName,
    sourceColorMode: sourceColorMode,
    crc32: crc,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );

  return ImageBinaryConversionResult(binaryBytes: output, metadata: metadata);
}

/// Reconstructs straight RGBA8888 pixel bytes from raw binary [binaryData] and [metadata].
Uint8List reconstructBinaryToRgba({
  required Uint8List binaryData,
  required ImageBinaryMetadata metadata,
}) {
  metadata.validateBinaryPayload(binaryData);

  final pixelCount = metadata.width * metadata.height;
  final rgba = Uint8List(pixelCount * 4);

  switch (metadata.pixelFormat) {
    case BinaryPixelFormat.rgb888:
      for (int p = 0, src = 0, dst = 0; p < pixelCount; p++, src += 3, dst += 4) {
        rgba[dst] = binaryData[src];
        rgba[dst + 1] = binaryData[src + 1];
        rgba[dst + 2] = binaryData[src + 2];
        rgba[dst + 3] = 255;
      }
      break;

    case BinaryPixelFormat.gray8:
      for (int p = 0, dst = 0; p < pixelCount; p++, dst += 4) {
        final v = binaryData[p];
        rgba[dst] = v;
        rgba[dst + 1] = v;
        rgba[dst + 2] = v;
        rgba[dst + 3] = 255;
      }
      break;

    case BinaryPixelFormat.mono1:
      for (int p = 0, dst = 0; p < pixelCount; p++, dst += 4) {
        final bit = (binaryData[p >> 3] >> (7 - (p & 7))) & 1;
        final v = bit == 1 ? 255 : 0;
        rgba[dst] = v;
        rgba[dst + 1] = v;
        rgba[dst + 2] = v;
        rgba[dst + 3] = 255;
      }
      break;
  }

  return rgba;
}

/// Computes exact RGB channel comparison metrics between [originalRgba] and [reconstructedRgba].
PixelComparisonMetrics compareRgbaBuffers(
  Uint8List originalRgba,
  Uint8List reconstructedRgba,
  int width,
  int height,
) {
  final pixelCount = width * height;
  if (originalRgba.length < pixelCount * 4 || reconstructedRgba.length < pixelCount * 4) {
    throw ArgumentError('RGBA buffers do not match image dimensions $width×$height.');
  }

  int identical = 0;
  int differing = 0;
  int maxDiff = 0;
  int totalAbsDiff = 0;

  for (int p = 0, i = 0; p < pixelCount; p++, i += 4) {
    final dr = (originalRgba[i] - reconstructedRgba[i]).abs();
    final dg = (originalRgba[i + 1] - reconstructedRgba[i + 1]).abs();
    final db = (originalRgba[i + 2] - reconstructedRgba[i + 2]).abs();

    if (dr == 0 && dg == 0 && db == 0) {
      identical++;
    } else {
      differing++;
      if (dr > maxDiff) maxDiff = dr;
      if (dg > maxDiff) maxDiff = dg;
      if (db > maxDiff) maxDiff = db;
      totalAbsDiff += dr + dg + db;
    }
  }

  final mae = pixelCount > 0 ? totalAbsDiff / (pixelCount * 3.0) : 0.0;
  return PixelComparisonMetrics(
    pixelCount: pixelCount,
    identicalRgbPixels: identical,
    differingRgbPixels: differing,
    maxChannelDiff: maxDiff,
    meanAbsoluteChannelError: mae,
  );
}

/// Formats only a single bounded page of bytes as 0s and 1s without converting the full file.
BinaryPreviewPage formatBinaryPage(
  Uint8List bytes, {
  required int pageIndex,
  int bytesPerPage = 64,
  int bytesPerRow = 4,
  int? totalValidBits,
}) {
  if (bytes.isEmpty) {
    return const BinaryPreviewPage(
      pageIndex: 0,
      totalPages: 1,
      startByte: 0,
      endByte: 0,
      rows: [],
    );
  }

  final totalPages = math.max(1, (bytes.length + bytesPerPage - 1) ~/ bytesPerPage);
  final safePage = pageIndex.clamp(0, totalPages - 1);
  final startByte = safePage * bytesPerPage;
  final endByte = math.min(bytes.length, startByte + bytesPerPage);

  final rows = <BinaryPreviewRow>[];
  for (int rowOffset = startByte; rowOffset < endByte; rowOffset += bytesPerRow) {
    final rowEnd = math.min(endByte, rowOffset + bytesPerRow);
    final sb = StringBuffer();
    for (int b = rowOffset; b < rowEnd; b++) {
      final remainingBits = totalValidBits != null ? (totalValidBits - (b * 8)) : 8;
      if (remainingBits <= 0) break;
      if (b > rowOffset) sb.write(' ');
      final fullBits = _kByteToBitsTable[bytes[b]];
      if (remainingBits < 8) {
        sb.write(fullBits.substring(0, remainingBits));
      } else {
        sb.write(fullBits);
      }
    }

    rows.add(
      BinaryPreviewRow(
        byteOffset: rowOffset,
        byteCount: rowEnd - rowOffset,
        offsetHex: rowOffset.toRadixString(16).toUpperCase().padLeft(8, '0'),
        bitsText: sb.toString(),
      ),
    );
  }

  return BinaryPreviewPage(
    pageIndex: safePage,
    totalPages: totalPages,
    startByte: startByte,
    endByte: endByte,
    rows: rows,
  );
}

/// Maximum raw byte size for which exporting an expanded 0/1 ASCII .txt representation is recommended.
const int kMaxTxtExportRawBytes = 2 * 1024 * 1024;

/// Maximum column-pair count for streaming a .compressed.txt representation.
const int kMaxCompressedTxtExportPairs = 2 * 1024 * 1024;

/// Maximum column-pair count for copying the full compressed text directly to the clipboard.
const int kMaxCopyFullCompressedPairs = 250000;

/// Text preview/export encoding modes supported in Step 3 & Step 4.
enum BinaryTextEncodingMode {
  standardBinary,
  columnPairCompressed,
}

/// Decoder preference when pasting binary or compressed text in Binary -> Image.
enum TextInputFormatPreference {
  auto,
  standardBinary,
  columnPairCompressed,
}

/// Single row produced by splitting the raw bitstream into two halves and comparing column pairs.
class CompressedPairRow {
  final int pairIndex;
  final String offsetHex;
  final int col1Bit;
  final int col2Bit;
  final String token;

  const CompressedPairRow({
    required this.pairIndex,
    required this.offsetHex,
    required this.col1Bit,
    required this.col2Bit,
    required this.token,
  });

  String get formattedLine => '$offsetHex  $token';
}

/// Bounded single-page view over the custom column-pair compressed representation.
class CompressedPreviewPage {
  final int pageIndex;
  final int totalPages;
  final int startPair;
  final int endPair;
  final int totalPairs;
  final bool hasOddPaddingBit;
  final List<CompressedPairRow> rows;

  const CompressedPreviewPage({
    required this.pageIndex,
    required this.totalPages,
    required this.startPair,
    required this.endPair,
    required this.totalPairs,
    required this.hasOddPaddingBit,
    required this.rows,
  });
}

/// Result of decoding pasted standard binary or signed-column compressed text.
class DecodedTextPayload {
  final Uint8List binaryBytes;
  final BinaryTextEncodingMode detectedEncoding;
  final int bitCount;
  final int pairCount;
  final ImageBinaryMetadata? headerMetadata;

  const DecodedTextPayload({
    required this.binaryBytes,
    required this.detectedEncoding,
    required this.bitCount,
    required this.pairCount,
    this.headerMetadata,
  });
}

/// Returns MSB-first bit [0 or 1] at [bitIndex] inside [bytes].
int _getBitMsb(Uint8List bytes, int bitIndex) {
  return (bytes[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1;
}

/// Sets bit at [bitIndex] (MSB-first) to 1 inside [bytes].
void _setBitMsb(Uint8List bytes, int bitIndex) {
  bytes[bitIndex >> 3] |= 1 << (7 - (bitIndex & 7));
}

/// Encodes a single pair of bits into its signed-column token:
/// identical -> '1-' or '0-'; different -> '1' or '0' (Column 1 only).
String encodeColumnPairToken(int col1Bit, int col2Bit) {
  if (col1Bit == col2Bit) {
    return col1Bit == 1 ? '1-' : '0-';
  }
  return col1Bit == 1 ? '1' : '0';
}

/// Formats only a single bounded page of the column-pair compressed single-column output.
CompressedPreviewPage formatCompressedBinaryPage(
  Uint8List bytes, {
  required int totalBits,
  required int pageIndex,
  int pairsPerPage = 64,
}) {
  if (bytes.isEmpty || totalBits <= 0) {
    return const CompressedPreviewPage(
      pageIndex: 0,
      totalPages: 1,
      startPair: 0,
      endPair: 0,
      totalPairs: 0,
      hasOddPaddingBit: false,
      rows: [],
    );
  }

  final hasOddPad = (totalBits & 1) == 1;
  final totalPairs = (totalBits + 1) >> 1;
  final totalPages = math.max(1, (totalPairs + pairsPerPage - 1) ~/ pairsPerPage);
  final safePage = pageIndex.clamp(0, totalPages - 1);
  final startPair = safePage * pairsPerPage;
  final endPair = math.min(totalPairs, startPair + pairsPerPage);

  final rows = <CompressedPairRow>[];
  for (int i = startPair; i < endPair; i++) {
    final b1 = _getBitMsb(bytes, i);
    final b2Index = i + totalPairs;
    final b2 = b2Index < totalBits ? _getBitMsb(bytes, b2Index) : 0;
    final token = encodeColumnPairToken(b1, b2);
    rows.add(
      CompressedPairRow(
        pairIndex: i,
        offsetHex: i.toRadixString(16).toUpperCase().padLeft(8, '0'),
        col1Bit: b1,
        col2Bit: b2,
        token: token,
      ),
    );
  }

  return CompressedPreviewPage(
    pageIndex: safePage,
    totalPages: totalPages,
    startPair: startPair,
    endPair: endPair,
    totalPairs: totalPairs,
    hasOddPaddingBit: hasOddPad,
    rows: rows,
  );
}

/// Shared metadata header comment block used by .txt and compressed text exports.
String buildTextExportHeader(
  ImageBinaryMetadata metadata, {
  String compression = 'none',
}) {
  final extraThreshold = metadata.threshold != null ? ' threshold=${metadata.threshold}' : '';
  final extraPairs = compression == 'col_pair_v1'
      ? ' pairs=${(metadata.totalBits + 1) >> 1} odd_pad=${(metadata.totalBits & 1) == 1 ? 1 : 0}'
      : '';
  return '# Magic Key Binary Representation\n'
      '# width=${metadata.width} height=${metadata.height} '
      'format=${metadata.pixelFormat.id} depth=${metadata.colorDepth} '
      'channels=${metadata.channelOrder} bits=${metadata.totalBits} '
      'bytes=${metadata.totalBytes} compression=$compression '
      'crc32=${metadata.crc32Hex}$extraThreshold$extraPairs '
      'file=${metadata.sourceFileName}\n';
}

/// Yields UTF-8 chunks of the 0/1 text representation without materializing a whole-file String.
Iterable<Uint8List> streamTxtChunks(
  Uint8List bytes,
  ImageBinaryMetadata metadata, {
  int bytesPerLine = 8,
  int chunkLineCount = 64,
}) sync* {
  yield Uint8List.fromList(
    utf8.encode(buildTextExportHeader(metadata, compression: 'none')),
  );

  final validBits = metadata.totalBits;
  final sb = StringBuffer();
  int linesInChunk = 0;

  for (int offset = 0; offset < bytes.length; offset += bytesPerLine) {
    final rowEnd = math.min(bytes.length, offset + bytesPerLine);
    sb.write(offset.toRadixString(16).toUpperCase().padLeft(8, '0'));
    sb.write(': ');
    for (int b = offset; b < rowEnd; b++) {
      final remaining = validBits - (b * 8);
      if (remaining <= 0) break;
      if (b > offset) sb.write(' ');
      final fullBits = _kByteToBitsTable[bytes[b]];
      if (remaining < 8) {
        sb.write(fullBits.substring(0, remaining));
      } else {
        sb.write(fullBits);
      }
    }
    sb.write('\n');
    linesInChunk++;

    if (linesInChunk >= chunkLineCount) {
      yield Uint8List.fromList(utf8.encode(sb.toString()));
      sb.clear();
      linesInChunk = 0;
    }
  }

  if (sb.isNotEmpty) {
    yield Uint8List.fromList(utf8.encode(sb.toString()));
  }
}

/// Yields UTF-8 chunks of the custom single-column compressed format ('1-', '0-', '1', '0').
Iterable<Uint8List> streamCompressedTxtChunks(
  Uint8List bytes,
  ImageBinaryMetadata metadata, {
  int chunkPairCount = 512,
}) sync* {
  yield Uint8List.fromList(
    utf8.encode(buildTextExportHeader(metadata, compression: 'col_pair_v1')),
  );

  final totalBits = metadata.totalBits;
  final totalPairs = (totalBits + 1) >> 1;
  final sb = StringBuffer();
  int countInChunk = 0;

  for (int i = 0; i < totalPairs; i++) {
    final b1 = _getBitMsb(bytes, i);
    final b2Index = i + totalPairs;
    final b2 = b2Index < totalBits ? _getBitMsb(bytes, b2Index) : 0;
    sb.write(encodeColumnPairToken(b1, b2));
    sb.write('\n');
    countInChunk++;

    if (countInChunk >= chunkPairCount) {
      yield Uint8List.fromList(utf8.encode(sb.toString()));
      sb.clear();
      countInChunk = 0;
    }
  }

  if (sb.isNotEmpty) {
    yield Uint8List.fromList(utf8.encode(sb.toString()));
  }
}

/// Materializes the full compressed text for small/medium payloads so users can copy in one tap.
String buildFullCompressedText(
  Uint8List bytes,
  ImageBinaryMetadata metadata, {
  bool includeHeader = true,
}) {
  final totalPairs = (metadata.totalBits + 1) >> 1;
  if (totalPairs > kMaxCopyFullCompressedPairs) {
    throw RangeError(
      'عدد الأزواج ($totalPairs) كبير جداً للنسخ الكامل إلى الحافظة؛ استخدم التصدير إلى ملف بدلاً من ذلك.',
    );
  }
  final sb = StringBuffer();
  for (final chunk in streamCompressedTxtChunks(bytes, metadata)) {
    final text = utf8.decode(chunk);
    if (!includeHeader && sb.isEmpty && text.startsWith('#')) {
      final lines = text.split('\n');
      for (final line in lines) {
        if (line.isNotEmpty && !line.startsWith('#')) {
          sb.writeln(line);
        }
      }
    } else {
      sb.write(text);
    }
  }
  return sb.toString().trimRight();
}

/// Extracts metadata from `# Magic Key` header comments in exported .txt or pasted text, if present.
({ImageBinaryMetadata? metadata, String? compression}) parseTextExportHeader(String rawText) {
  int? width;
  int? height;
  String? formatStr;
  int? bits;
  int? bytes;
  int? threshold;
  int? crc32;
  String? compression;
  String? fileName;

  for (final rawLine in rawText.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('#')) continue;

    final widthMatch = RegExp(r'\bwidth=(\d+)').firstMatch(line);
    if (widthMatch != null) width = int.tryParse(widthMatch.group(1)!);

    final heightMatch = RegExp(r'\bheight=(\d+)').firstMatch(line);
    if (heightMatch != null) height = int.tryParse(heightMatch.group(1)!);

    final formatMatch = RegExp(r'\bformat=([A-Za-z0-9_]+)').firstMatch(line);
    if (formatMatch != null) formatStr = formatMatch.group(1);

    final bitsMatch = RegExp(r'\bbits=(\d+)').firstMatch(line);
    if (bitsMatch != null) bits = int.tryParse(bitsMatch.group(1)!);

    final bytesMatch = RegExp(r'\bbytes=(\d+)').firstMatch(line);
    if (bytesMatch != null) bytes = int.tryParse(bytesMatch.group(1)!);

    final thrMatch = RegExp(r'\bthreshold=(\d+)').firstMatch(line);
    if (thrMatch != null) threshold = int.tryParse(thrMatch.group(1)!);

    final compMatch = RegExp(r'\bcompression=([A-Za-z0-9_]+)').firstMatch(line);
    if (compMatch != null) compression = compMatch.group(1);

    final crcMatch = RegExp(r'\bcrc32=([0-9A-Fa-f]{1,8})').firstMatch(line);
    if (crcMatch != null) crc32 = int.tryParse(crcMatch.group(1)!, radix: 16);

    final fileMatch = RegExp(r'\bfile=(.+)$').firstMatch(line);
    if (fileMatch != null) fileName = fileMatch.group(1)?.trim();
  }

  if (width == null || height == null || formatStr == null || width <= 0 || height <= 0) {
    return (metadata: null, compression: compression);
  }

  final pixelFormat = BinaryPixelFormatMeta.fromId(formatStr);
  final pixelCount = width * height;
  final expectedBits = switch (pixelFormat) {
    BinaryPixelFormat.rgb888 => pixelCount * 24,
    BinaryPixelFormat.gray8 => pixelCount * 8,
    BinaryPixelFormat.mono1 => pixelCount,
  };
  final expectedBytes = switch (pixelFormat) {
    BinaryPixelFormat.rgb888 => pixelCount * 3,
    BinaryPixelFormat.gray8 => pixelCount,
    BinaryPixelFormat.mono1 => (pixelCount + 7) >> 3,
  };

  final resolvedBits = bits ?? expectedBits;
  final meta = ImageBinaryMetadata(
    width: width,
    height: height,
    pixelFormat: pixelFormat,
    colorDepth: pixelFormat.colorDepth,
    bitDepthPerChannel: pixelFormat.bitDepthPerChannel,
    channelOrder: pixelFormat.channelOrder,
    pixelCount: pixelCount,
    totalBytes: bytes ?? expectedBytes,
    totalBits: resolvedBits,
    paddingBits: pixelFormat == BinaryPixelFormat.mono1 ? (8 - (resolvedBits % 8)) % 8 : 0,
    threshold: threshold,
    isLossless: pixelFormat.isLosslessRgb,
    sourceFileName: fileName ?? 'pasted_input',
    sourceColorMode: 'Text Import',
    crc32: crc32 ?? 0,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );

  return (metadata: meta, compression: compression);
}

/// Strips `#` comments and optional hex row offsets (`00000000:` or `00000000  `) from pasted data lines.
List<String> _extractDataLines(String rawText) {
  final lines = <String>[];
  final hexColonPrefix = RegExp(r'^[0-9A-Fa-f]{4,16}:\s+');
  final hexSpacePrefix = RegExp(r'^[0-9A-Fa-f]{8}\s{2,}');

  for (final rawLine in rawText.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    line = line.replaceFirst(hexColonPrefix, '');
    line = line.replaceFirst(hexSpacePrefix, '');
    line = line.trim();
    if (line.isNotEmpty) lines.add(line);
  }
  return lines;
}

/// Auto-detects whether pasted text uses standard 0/1 binary or custom signed-column compression ('1-', '0').
BinaryTextEncodingMode detectPastedTextFormat(
  String rawText, {
  ImageBinaryMetadata? expectedMetadata,
}) {
  final parsedHeader = parseTextExportHeader(rawText);
  if (parsedHeader.compression == 'col_pair_v1') {
    return BinaryTextEncodingMode.columnPairCompressed;
  }
  if (parsedHeader.compression == 'none') {
    return BinaryTextEncodingMode.standardBinary;
  }

  final lines = _extractDataLines(rawText);
  if (lines.isEmpty) {
    return BinaryTextEncodingMode.standardBinary;
  }

  final tokens = lines.expand((l) => l.split(RegExp(r'\s+'))).where((t) => t.isNotEmpty).toList();
  if (tokens.any((t) => t == '0-' || t == '1-')) {
    return BinaryTextEncodingMode.columnPairCompressed;
  }

  // Edge case: all column pairs happened to differ (every token is single '0' or '1' on its own line)
  final allSingleBitLines = lines.every((l) => l == '0' || l == '1');
  if (allSingleBitLines) {
    final targetBits = (expectedMetadata ?? parsedHeader.metadata)?.totalBits;
    if (targetBits != null && ((targetBits + 1) >> 1) == lines.length && targetBits != lines.length) {
      return BinaryTextEncodingMode.columnPairCompressed;
    }
  }

  return BinaryTextEncodingMode.standardBinary;
}

/// Decodes pasted standard binary ('0'/'1') or custom column-pair compressed ('1-'/'0-'/'1'/'0') text.
DecodedTextPayload decodePastedTextToBinary({
  required String rawText,
  ImageBinaryMetadata? fallbackMetadata,
  TextInputFormatPreference preference = TextInputFormatPreference.auto,
}) {
  final headerParsed = parseTextExportHeader(rawText);
  final effectiveMeta = fallbackMetadata ?? headerParsed.metadata;
  final lines = _extractDataLines(rawText);
  if (lines.isEmpty) {
    throw const FormatException('النص الملصق فارغ أو لا يحتوي على بيانات ثنائية.');
  }

  final encoding = switch (preference) {
    TextInputFormatPreference.auto => detectPastedTextFormat(
        rawText,
        expectedMetadata: effectiveMeta,
      ),
    TextInputFormatPreference.standardBinary => BinaryTextEncodingMode.standardBinary,
    TextInputFormatPreference.columnPairCompressed => BinaryTextEncodingMode.columnPairCompressed,
  };

  if (encoding == BinaryTextEncodingMode.columnPairCompressed) {
    final tokens = <String>[];
    for (final line in lines) {
      for (final token in line.split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        if (token != '0' && token != '1' && token != '0-' && token != '1-') {
          throw FormatException(
            'رمز غير صالح في التنسيق المضغوط: "$token". الرموز المسموحة هي: 1- و 0- و 1 و 0.',
          );
        }
        tokens.add(token);
      }
    }

    if (tokens.isEmpty) {
      throw const FormatException('لم يتم العثور على أي رموز مضغوطة صالحة.');
    }

    final pairCount = tokens.length;
    final maxBitsFromPairs = pairCount * 2;
    final targetBits = effectiveMeta?.totalBits ?? maxBitsFromPairs;

    if (effectiveMeta != null) {
      final expectedPairs = (effectiveMeta.totalBits + 1) >> 1;
      if (pairCount != expectedPairs) {
        throw FormatException(
          'عدد الصفوف المضغوطة ($pairCount) لا يطابق العدد المتوقع ($expectedPairs) لـ ${effectiveMeta.totalBits} بت.',
        );
      }
    }

    final outBytes = Uint8List((targetBits + 7) >> 3);
    for (int i = 0; i < pairCount; i++) {
      final tok = tokens[i];
      final int b1;
      final int b2;
      if (tok == '1-') {
        b1 = 1;
        b2 = 1;
      } else if (tok == '0-') {
        b1 = 0;
        b2 = 0;
      } else if (tok == '1') {
        b1 = 1;
        b2 = 0;
      } else {
        b1 = 0;
        b2 = 1;
      }

      if (b1 == 1) {
        _setBitMsb(outBytes, i);
      }
      final col2Index = i + pairCount;
      if (col2Index < targetBits && b2 == 1) {
        _setBitMsb(outBytes, col2Index);
      }
    }

    return DecodedTextPayload(
      binaryBytes: outBytes,
      detectedEncoding: BinaryTextEncodingMode.columnPairCompressed,
      bitCount: targetBits,
      pairCount: pairCount,
      headerMetadata: headerParsed.metadata,
    );
  }

  // Standard 0/1 binary text parsing
  final bits = <int>[];
  for (final line in lines) {
    for (int i = 0; i < line.length; i++) {
      final code = line.codeUnitAt(i);
      if (code == 0x30) {
        bits.add(0);
      } else if (code == 0x31) {
        bits.add(1);
      } else if (code == 0x20 || code == 0x09 || code == 0x0D) {
        continue;
      } else {
        throw FormatException(
          'محرف غير صالح في البيانات الثنائية القياسية: "${line[i]}". يُسمح فقط بـ 0 و 1.',
        );
      }
    }
  }

  if (bits.isEmpty) {
    throw const FormatException('لم يتم العثور على أي بتات (0 أو 1) في النص الملصق.');
  }

  if (effectiveMeta != null && bits.length != effectiveMeta.totalBits) {
    throw FormatException(
      'عدد البتات الملصقة (${bits.length}) لا يطابق العدد المطلوب (${effectiveMeta.totalBits} بت) للأبعاد ${effectiveMeta.width}×${effectiveMeta.height}.',
    );
  }

  final outBytes = Uint8List((bits.length + 7) >> 3);
  for (int i = 0; i < bits.length; i++) {
    if (bits[i] == 1) {
      _setBitMsb(outBytes, i);
    }
  }

  return DecodedTextPayload(
    binaryBytes: outBytes,
    detectedEncoding: BinaryTextEncodingMode.standardBinary,
    bitCount: bits.length,
    pairCount: 0,
    headerMetadata: headerParsed.metadata,
  );
}

/// Reads a [FileSource] in bounded chunks so large files are processed safely on-device.
Future<Uint8List> readFileSourceBytes(
  FileSource source, {
  int maxBytes = 64 * 1024 * 1024,
  int chunkSize = 262144,
}) async {
  if (source.size > maxBytes) {
    throw FormatException(
      'حجم الملف (${source.formattedSize}) يتجاوز الحد الآمن للمعالجة المحلية (${maxBytes ~/ (1024 * 1024)} MB).',
    );
  }

  if (source.path != null && source.path!.isNotEmpty) {
    final file = File(source.path!);
    final builder = BytesBuilder(copy: false);
    int total = 0;
    await for (final chunk in file.openRead()) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const FormatException('تجاوز الملف الحد الآمن للمعالجة المحلية.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  final builder = BytesBuilder(copy: false);
  int offset = 0;
  while (true) {
    final chunk = await source.readChunk(offset, chunkSize);
    if (chunk.isEmpty) break;
    if (offset + chunk.length > maxBytes) {
      throw const FormatException('تجاوز الملف الحد الآمن للمعالجة المحلية.');
    }
    builder.add(chunk);
    offset += chunk.length;
    if (source.size > 0 && offset >= source.size) break;
  }
  return builder.takeBytes();
}

/// Decodes PNG, JPEG, or WEBP bytes into straight RGBA8888 pixel bytes using Flutter's native codec.
Future<DecodedImageInfo> decodeImageBytesToRgba({
  required Uint8List fileBytes,
  required String fileName,
  required int fileSizeBytes,
}) async {
  final header = ImageHeaderInfo.inspect(fileBytes);
  if (header == null) {
    throw const FormatException(
      'صيغة الصورة غير مدعومة. الصيغ المدعومة هي: PNG، JPG، JPEG، WEBP.',
    );
  }

  final codec = await ui.instantiateImageCodec(fileBytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (byteData == null) {
        throw StateError('تعذر استخراج بيانات البكسلات الخام من الصورة.');
      }
      final rgbaBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final hasAlpha = detectAlphaInRgba(rgbaBytes);

      return DecodedImageInfo(
        rgbaBytes: rgbaBytes,
        width: image.width,
        height: image.height,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes > 0 ? fileSizeBytes : fileBytes.length,
        detectedFormat: header.formatId,
        colorMode: header.colorMode,
        hasTransparentPixels: hasAlpha,
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Encodes straight RGBA8888 pixel bytes (opaque alpha=255) into a lossless PNG buffer for display.
Future<Uint8List> encodeRgbaToPngBytes({
  required Uint8List rgbaBytes,
  required int width,
  required int height,
}) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgbaBytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (ui.Image img) => completer.complete(img),
  );
  final image = await completer.future;
  try {
    final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (pngData == null) {
      throw StateError('تعذر ترميز الصورة المعاد بناؤها إلى PNG.');
    }
    return pngData.buffer.asUint8List(pngData.offsetInBytes, pngData.lengthInBytes);
  } finally {
    image.dispose();
  }
}
