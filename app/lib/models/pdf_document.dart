/// Metadata for an individual page in a PDF document.
class PdfPageInfo {
  final int pageIndex;
  final int width;
  final int height;

  const PdfPageInfo({
    required this.pageIndex,
    required this.width,
    required this.height,
  });

  /// The width-to-height aspect ratio of the page (e.g. 595 / 842 ≈ 0.706 for A4).
  double get aspectRatio => height > 0 ? width / height : 1.0;

  factory PdfPageInfo.fromJson(Map<String, dynamic> json) {
    return PdfPageInfo(
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 595,
      height: (json['height'] as num?)?.toInt() ?? 842,
    );
  }
}

/// Structured document representation for an active PDF viewing session.
class PdfDocument {
  final String sessionId;
  final int pageCount;
  final List<PdfPageInfo> pages;

  const PdfDocument({
    required this.sessionId,
    required this.pageCount,
    required this.pages,
  });

  factory PdfDocument.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'] as List<dynamic>? ?? [];
    final pages = rawPages
        .map((p) => PdfPageInfo.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();

    return PdfDocument(
      sessionId: json['sessionId'] as String? ?? '',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? pages.length,
      pages: pages,
    );
  }
}
