import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/detection_result.dart';
import '../models/file_source.dart';
import '../models/pdf_document.dart';
import '../services/pdf_service.dart';

/// Native-quality, low-memory PDF Document Viewing Engine.
class PdfViewer extends StatefulWidget {
  final FileSource fileSource;
  final DetectionResult detectionResult;
  final VoidCallback? onOpenInHex;

  const PdfViewer({
    super.key,
    required this.fileSource,
    required this.detectionResult,
    this.onOpenInHex,
  });

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  final PdfService _pdfService = PdfService.instance;
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  String? _errorMessage;
  bool _isEncrypted = false;
  bool _isMalformed = false;
  PdfDocument? _document;
  int _currentPage = 1;

  final Map<int, Uint8List> _renderedPages = {};
  final Set<int> _activeRenders = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPdfDocument();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (_document != null && _document!.sessionId.isNotEmpty) {
      _pdfService.closePdf(_document!.sessionId);
    }
    super.dispose();
  }

  Future<void> _loadPdfDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isEncrypted = false;
      _isMalformed = false;
    });

    try {
      final doc = await _pdfService.openPdf(widget.fileSource);
      if (!mounted) return;

      setState(() {
        _document = doc;
        _isLoading = false;
        _currentPage = 1;
      });
    } on PdfException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isEncrypted = e.isEncrypted;
        _isMalformed = e.isMalformed;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _onScroll() {
    if (_document == null || _document!.pageCount <= 1 || !_scrollController.hasClients) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset.clamp(0.0, maxScroll);

    if (maxScroll <= 0) return;

    final progress = currentScroll / maxScroll;
    final estimatedPage = (progress * (_document!.pageCount - 1)).round() + 1;
    final clampedPage = estimatedPage.clamp(1, _document!.pageCount);

    if (clampedPage != _currentPage) {
      setState(() {
        _currentPage = clampedPage;
      });
    }
  }

  void _scrollToPage(int pageNumber) {
    if (_document == null || !_scrollController.hasClients) return;
    final targetPage = pageNumber.clamp(1, _document!.pageCount);

    final maxScroll = _scrollController.position.maxScrollExtent;
    final targetOffset = ((targetPage - 1) / (_document!.pageCount - 1).clamp(1, 999999)) * maxScroll;

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _showJumpToPageDialog(BuildContext context) async {
    if (_document == null || _document!.pageCount <= 1) return;

    final l10n = AppLocalizations.of(context);
    final textController = TextEditingController(text: '$_currentPage');

    final selectedPage = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.get('pdfJumpToPage')),
          content: TextField(
            controller: textController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '1 - ${_document!.pageCount}',
              suffixText: '/ ${_document!.pageCount}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.get('pdfCancel')),
            ),
            ElevatedButton(
              onPressed: () {
                final page = int.tryParse(textController.text.trim());
                if (page != null && page >= 1 && page <= _document!.pageCount) {
                  Navigator.of(context).pop(page);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.get('pdfInvalidPage')),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Text(l10n.get('pdfGoTo')),
            ),
          ],
        );
      },
    );

    if (selectedPage != null) {
      _scrollToPage(selectedPage);
    }
  }

  Future<void> _renderPageIfNeeded(int pageIndex, int targetWidth) async {
    if (_document == null ||
        _renderedPages.containsKey(pageIndex) ||
        _activeRenders.contains(pageIndex)) {
      return;
    }

    _activeRenders.add(pageIndex);

    try {
      final bytes = await _pdfService.renderPage(
        sessionId: _document!.sessionId,
        pageIndex: pageIndex,
        targetWidth: targetWidth,
      );

      if (mounted) {
        setState(() {
          _renderedPages[pageIndex] = bytes;
          _activeRenders.remove(pageIndex);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeRenders.remove(pageIndex);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Rendering PDF...',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null || _isEncrypted || _isMalformed) {
      return _buildErrorState(context, isDark, l10n);
    }

    if (_document == null || _document!.pageCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(l10n.get('pdfEmpty'), style: const TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    final pageCount = _document!.pageCount;

    return Stack(
      children: [
        // Multi-page Vertical Scrolling Viewport with Zoom
        InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              // Render target width scaled by pixel density
              final targetWidth = (viewportWidth * MediaQuery.of(context).devicePixelRatio).toInt().clamp(720, 2160);

              return ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: pageCount,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return _buildPageCard(context, index, viewportWidth, targetWidth, isDark);
                },
              );
            },
          ),
        ),

        // Floating Page Indicator & Quick Jump Pill
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: isDark ? const Color(0xFF1E293B).withOpacity(0.92) : Colors.white.withOpacity(0.94),
              elevation: 4,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _showJumpToPageDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.layers_outlined, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.get('pdfPageIndicator').replaceAll('{current}', '$_currentPage').replaceAll('{total}', '$pageCount'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.unfold_more, size: 14, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageCard(
    BuildContext context,
    int pageIndex,
    double viewportWidth,
    int targetWidth,
    bool isDark,
  ) {
    final pageInfo = _document!.pages[pageIndex];
    final cardWidth = (viewportWidth - 32).clamp(100.0, 960.0);
    final cardHeight = cardWidth / pageInfo.aspectRatio;

    final bytes = _renderedPages[pageIndex];

    if (bytes == null) {
      _renderPageIfNeeded(pageIndex, targetWidth);
    }

    return Center(
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(
                bytes,
                width: cardWidth,
                height: cardHeight,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              )
            : Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, bool isDark, AppLocalizations l10n) {
    final theme = Theme.of(context);

    final title = _isEncrypted
        ? l10n.get('pdfEncryptedTitle')
        : (_isMalformed ? l10n.get('pdfMalformedTitle') : 'PDF Rendering Error');

    final desc = _isEncrypted
        ? l10n.get('pdfEncryptedDesc')
        : (_isMalformed ? l10n.get('pdfMalformedDesc') : (_errorMessage ?? 'An error occurred while parsing the PDF.'));

    final icon = _isEncrypted
        ? Icons.lock_outline
        : (_isMalformed ? Icons.broken_image_outlined : Icons.error_outline);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                child: Icon(icon, size: 36, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 28),
              if (widget.onOpenInHex != null)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: widget.onOpenInHex,
                    icon: const Icon(Icons.data_object, size: 20),
                    label: Text(l10n.get('openHexButton')),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _loadPdfDocument,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
