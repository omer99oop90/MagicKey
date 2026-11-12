import 'package:flutter/material.dart';
import '../models/detection_result.dart';
import '../models/file_source.dart';
import '../viewers/hex_viewer.dart';
import '../viewers/image_viewer.dart';
import '../viewers/pdf_viewer.dart';
import '../viewers/text_code_viewer.dart';
import '../viewers/unsupported_viewer.dart';
import '../widgets/diagnostic_banner.dart';

/// Universal file viewing screen dispatching to modular viewer engines.
class ViewerScreen extends StatefulWidget {
  final FileSource fileSource;
  final DetectionResult detectionResult;

  const ViewerScreen({
    super.key,
    required this.fileSource,
    required this.detectionResult,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late bool _forceHexView;

  @override
  void initState() {
    super.initState();
    // Default to Hex view if suggested by detection or if binary/unsupported
    _forceHexView = widget.detectionResult.suggestedViewer.toLowerCase() == 'hex';
  }

  Widget _buildActiveViewer() {
    if (_forceHexView) {
      return HexViewer(fileSource: widget.fileSource);
    }

    final viewerType = widget.detectionResult.suggestedViewer.toLowerCase();

    switch (viewerType) {
      case 'image':
        return ImageViewer(
          fileSource: widget.fileSource,
          formatId: widget.detectionResult.formatId,
        );
      case 'text_code':
        return TextCodeViewer(
          fileSource: widget.fileSource,
          formatId: widget.detectionResult.formatId,
        );
      case 'document':
        if (widget.detectionResult.formatId == 'pdf') {
          return PdfViewer(
            fileSource: widget.fileSource,
            detectionResult: widget.detectionResult,
            onOpenInHex: () {
              setState(() {
                _forceHexView = true;
              });
            },
          );
        }
        return UnsupportedViewer(
          fileSource: widget.fileSource,
          detectionResult: widget.detectionResult,
          onOpenInHex: () {
            setState(() {
              _forceHexView = true;
            });
          },
        );
      case 'media':
      case 'archive':
      default:
        return UnsupportedViewer(
          fileSource: widget.fileSource,
          detectionResult: widget.detectionResult,
          onOpenInHex: () {
            setState(() {
              _forceHexView = true;
            });
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final det = widget.detectionResult;

    final isMisnamed = det.details.contains('corrupted') ||
        det.details.contains('misnamed') ||
        (det.formatId == 'unknown_binary' && widget.fileSource.extensionHint.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Close file and return home',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileSource.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    det.displayName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.fileSource.formattedSize,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _forceHexView ? Icons.visibility : Icons.data_object,
              color: _forceHexView ? theme.colorScheme.primary : null,
            ),
            tooltip: _forceHexView ? 'Switch to Normal View' : 'Inspect in Hex Viewer',
            onPressed: () {
              setState(() {
                _forceHexView = !_forceHexView;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Diagnostic Banner for Misnamed / Corrupted files
          if (isMisnamed)
            DiagnosticBanner(
              title: 'Format Mismatch Notice',
              message: det.details,
              actionLabel: _forceHexView ? null : 'Open Hex',
              onAction: _forceHexView
                  ? null
                  : () {
                      setState(() {
                        _forceHexView = true;
                      });
                    },
            ),

          // Active Engine Viewport
          Expanded(child: _buildActiveViewer()),
        ],
      ),
    );
  }
}
