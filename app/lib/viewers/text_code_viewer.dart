import 'package:flutter/material.dart';
import '../models/file_source.dart';

/// Lightweight virtualized text and source-code viewer with bounded stream reading.
class TextCodeViewer extends StatefulWidget {
  final FileSource fileSource;
  final String formatId;

  const TextCodeViewer({
    super.key,
    required this.fileSource,
    required this.formatId,
  });

  @override
  State<TextCodeViewer> createState() => _TextCodeViewerState();
}

class _TextCodeViewerState extends State<TextCodeViewer> {
  String _content = '';
  bool _isLoading = true;
  String? _errorMessage;
  bool _wrapLines = false;
  int _lineCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTextContent();
  }

  Future<void> _loadTextContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Bounded read: reads up to 1 MB of text to prevent OOM
      final text = await widget.fileSource.readText(maxBytes: 1024 * 1024);
      final lines = text.split('\n');

      setState(() {
        _content = text;
        _lineCount = lines.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to read text stream: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTextContent,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final lines = _content.split('\n');

    return Column(
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '$_lineCount lines',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _wrapLines ? Icons.wrap_text : Icons.format_align_left,
                  size: 20,
                ),
                tooltip: _wrapLines ? 'Disable line wrap' : 'Enable line wrap',
                onPressed: () => setState(() => _wrapLines = !_wrapLines),
              ),
            ],
          ),
        ),

        // Text Viewer Area
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF020617) : Colors.white,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final lineNumber = (index + 1).toString().padLeft(4, ' ');
                final lineText = lines[index];

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line Number Gutter
                    Container(
                      width: 50,
                      padding: const EdgeInsets.only(right: 12),
                      alignment: Alignment.topRight,
                      child: Text(
                        lineNumber,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),

                    // Code Line
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: _wrapLines ? Axis.vertical : Axis.horizontal,
                        physics: _wrapLines ? const NeverScrollableScrollPhysics() : null,
                        child: Text(
                          lineText,
                          softWrap: _wrapLines,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.4,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
