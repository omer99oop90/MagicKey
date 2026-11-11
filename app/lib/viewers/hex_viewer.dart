import 'package:flutter/material.dart';
import '../ffi/core_bindings.dart';
import '../models/file_source.dart';
import '../models/hex_chunk.dart';

/// Virtualized 16-byte Hex Viewer connected directly to the Magic Key Rust core.
class HexViewer extends StatefulWidget {
  final FileSource fileSource;

  const HexViewer({
    super.key,
    required this.fileSource,
  });

  @override
  State<HexViewer> createState() => _HexViewerState();
}

class _HexViewerState extends State<HexViewer> {
  final CoreBindings _bindings = CoreBindings.instance;

  int _currentOffset = 0;
  static const int _pageSize = 256; // 16 rows of 16 bytes per chunk page
  HexChunk? _currentChunk;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChunk(_currentOffset);
  }

  Future<void> _loadChunk(int offset) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      HexChunk chunk;
      if (widget.fileSource.path != null && widget.fileSource.path!.isNotEmpty) {
        chunk = _bindings.readHexChunk(
          widget.fileSource.path!,
          offset: offset,
          maxBytes: _pageSize,
        );
      } else {
        // Android SAF content:// stream: read bounded chunk and format in Rust
        final bytes = await widget.fileSource.readChunk(offset, _pageSize);
        final totalSize = widget.fileSource.size > 0 ? widget.fileSource.size : offset + bytes.length;
        chunk = _bindings.formatHexChunk(
          bytes,
          offset: offset,
          totalSize: totalSize,
        );
      }

      setState(() {
        _currentOffset = offset;
        _currentChunk = chunk;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load hex chunk: $e';
        _isLoading = false;
      });
    }
  }

  void _previousPage() {
    if (_currentOffset >= _pageSize) {
      _loadChunk(_currentOffset - _pageSize);
    } else if (_currentOffset > 0) {
      _loadChunk(0);
    }
  }

  void _nextPage() {
    if (_currentChunk != null && !_currentChunk!.isEof) {
      _loadChunk(_currentOffset + _pageSize);
    }
  }

  Future<void> _showJumpDialog() async {
    final controller = TextEditingController(text: '0x${_currentOffset.toRadixString(16).toUpperCase()}');
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Byte Offset'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Hex (e.g. 0x100) or Decimal (e.g. 256)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              int? offset;
              if (text.startsWith('0x') || text.startsWith('0X')) {
                offset = int.tryParse(text.substring(2), radix: 16);
              } else {
                offset = int.tryParse(text);
              }
              Navigator.pop(ctx, offset);
            },
            child: const Text('Jump'),
          ),
        ],
      ),
    );

    if (target != null && target >= 0) {
      // Align to 16-byte boundary
      final aligned = (target ~/ 16) * 16;
      _loadChunk(aligned);
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
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadChunk(_currentOffset),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final chunk = _currentChunk!;
    final canPrev = _currentOffset > 0;
    final canNext = !chunk.isEof;

    return Column(
      children: [
        // Navigation Toolbar
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
                'Offset: 0x${_currentOffset.toRadixString(16).padLeft(8, '0').toUpperCase()} (${_currentOffset} B)',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Jump'),
                onPressed: _showJumpDialog,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous Page (256 B)',
                onPressed: canPrev ? _previousPage : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next Page (256 B)',
                onPressed: canNext ? _nextPage : null,
              ),
            ],
          ),
        ),

        // 16-Byte Hex Grid
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF020617) : Colors.white,
            child: chunk.rows.isEmpty
                ? const Center(
                    child: Text(
                      'No byte rows in current chunk (EOF or empty file).',
                      style: TextStyle(fontFamily: 'monospace'),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 720,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        itemCount: chunk.rows.length,
                        itemBuilder: (context, index) {
                          final row = chunk.rows[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: Text(
                              row.formattedLine,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                letterSpacing: 0.5,
                                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ),

        // Status Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                'Read ${chunk.bytesRead} bytes | Total: ${widget.fileSource.formattedSize}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const Spacer(),
              if (chunk.isEof)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'EOF REACHED',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
