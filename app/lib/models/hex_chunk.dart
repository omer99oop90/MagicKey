/// A single formatted 16-byte row in the Hex viewer.
class HexRow {
  final int offset;
  final int byteCount;
  final String hexDump;
  final String asciiDump;
  final String formattedLine;

  const HexRow({
    required this.offset,
    required this.byteCount,
    required this.hexDump,
    required this.asciiDump,
    required this.formattedLine,
  });

  factory HexRow.fromJson(Map<String, dynamic> json) {
    return HexRow(
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      byteCount: (json['byte_count'] as num?)?.toInt() ?? 0,
      hexDump: json['hex_dump'] as String? ?? '',
      asciiDump: json['ascii_dump'] as String? ?? '',
      formattedLine: json['formatted_line'] as String? ?? '',
    );
  }
}

/// A bounded chunk of formatted Hex data emitted by the Hex Engine.
class HexChunk {
  final int startOffset;
  final int bytesRead;
  final int totalFileSize;
  final List<HexRow> rows;
  final bool isEof;

  const HexChunk({
    required this.startOffset,
    required this.bytesRead,
    required this.totalFileSize,
    required this.rows,
    required this.isEof,
  });

  factory HexChunk.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List<dynamic>? ?? [];
    final parsedRows = rawRows
        .map((r) => HexRow.fromJson(r as Map<String, dynamic>))
        .toList();

    return HexChunk(
      startOffset: (json['start_offset'] as num?)?.toInt() ?? 0,
      bytesRead: (json['bytes_read'] as num?)?.toInt() ?? 0,
      totalFileSize: (json['total_file_size'] as num?)?.toInt() ?? 0,
      rows: parsedRows,
      isEof: json['is_eof'] as bool? ?? true,
    );
  }
}
