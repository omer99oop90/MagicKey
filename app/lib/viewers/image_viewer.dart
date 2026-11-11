import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/file_source.dart';

/// Interactive Image Viewer with 2D pan and pinch-to-zoom gestures.
class ImageViewer extends StatefulWidget {
  final FileSource fileSource;
  final String formatId;

  const ImageViewer({
    super.key,
    required this.fileSource,
    required this.formatId,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _errorMessage;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Read image bytes (up to 25 MB ceiling for single image viewport)
      final maxBytes = widget.fileSource.size > 0
          ? widget.fileSource.size.clamp(0, 25 * 1024 * 1024)
          : 25 * 1024 * 1024;

      final bytes = await widget.fileSource.readChunk(0, maxBytes);
      if (bytes.isEmpty) {
        throw StateError('Image stream yielded 0 bytes');
      }

      setState(() {
        _imageBytes = bytes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load image: $e';
        _isLoading = false;
      });
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_errorMessage != null || _imageBytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              Text(_errorMessage ?? 'Failed to decode image', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadImage,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final isSvg = widget.formatId.toLowerCase() == 'svg';

    return Stack(
      children: [
        // Zoomable Viewport Area
        Center(
          child: InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.5,
            maxScale: 10.0,
            boundaryMargin: const EdgeInsets.all(48),
            child: isSvg
                ? SvgPicture.memory(
                    _imageBytes!,
                    placeholderBuilder: (_) => const CircularProgressIndicator.adaptive(),
                  )
                : Image.memory(
                    _imageBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, __) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                          const SizedBox(height: 8),
                          Text('Image decoding error: $error'),
                        ],
                      ),
                    ),
                  ),
          ),
        ),

        // Quick Controls Overlay
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.small(
            onPressed: _resetZoom,
            tooltip: 'Reset Zoom (1:1)',
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            foregroundColor: isDark ? Colors.white : Colors.black87,
            child: const Icon(Icons.aspect_ratio),
          ),
        ),
      ],
    );
  }
}
