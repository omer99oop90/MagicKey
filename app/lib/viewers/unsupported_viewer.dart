import 'package:flutter/material.dart';
import '../models/detection_result.dart';
import '../models/file_source.dart';

/// Clean fallback viewport presenting metadata and routing to the Hex Viewer.
class UnsupportedViewer extends StatelessWidget {
  final FileSource fileSource;
  final DetectionResult detectionResult;
  final VoidCallback onOpenInHex;

  const UnsupportedViewer({
    super.key,
    required this.fileSource,
    required this.detectionResult,
    required this.onOpenInHex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Icon(
                  Icons.insert_drive_file_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                detectionResult.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Format Details Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${detectionResult.mimeType} • ${fileSource.formattedSize}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Explanation Message
              Text(
                detectionResult.details.isNotEmpty
                    ? detectionResult.details
                    : 'A native graphical engine for this format is not available in the current phase. You can inspect the raw bytes and structure using the Universal Hex Viewer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 32),

              // Primary Action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onOpenInHex,
                  icon: const Icon(Icons.data_object, size: 20),
                  label: const Text('Inspect Raw Bytes in Hex'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
