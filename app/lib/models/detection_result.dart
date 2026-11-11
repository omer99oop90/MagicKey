/// Structured detection result emitted by the Magic Key core engine.
class DetectionResult {
  final String formatId;
  final String displayName;
  final String mimeType;
  final String category;
  final String confidence;
  final String detectionMethod;
  final String suggestedViewer;
  final String details;

  const DetectionResult({
    required this.formatId,
    required this.displayName,
    required this.mimeType,
    required this.category,
    required this.confidence,
    required this.detectionMethod,
    required this.suggestedViewer,
    required this.details,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      formatId: json['format_id'] as String? ?? 'unknown',
      displayName: json['display_name'] as String? ?? 'Unknown Format',
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      category: json['category'] as String? ?? 'binary',
      confidence: json['confidence'] as String? ?? 'unknown',
      detectionMethod: json['detection_method'] as String? ?? 'unknown_binary',
      suggestedViewer: json['suggested_viewer'] as String? ?? 'hex',
      details: json['details'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'format_id': formatId,
        'display_name': displayName,
        'mime_type': mimeType,
        'category': category,
        'confidence': confidence,
        'detection_method': detectionMethod,
        'suggested_viewer': suggestedViewer,
        'details': details,
      };

  bool get isHighConfidence => confidence.toLowerCase() == 'high';
  bool get isHexFallback => suggestedViewer.toLowerCase() == 'hex';
}
