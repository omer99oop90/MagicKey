import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_source.dart';
import '../services/file_service.dart';
import '../services/image_binary_codec.dart';

/// Self-contained Arabic RTL page for Image-to-Binary conversion and Binary-to-Image reconstruction.
class ImageToBinaryScreen extends StatefulWidget {
  final FileService? fileService;

  const ImageToBinaryScreen({
    super.key,
    this.fileService,
  });

  @override
  State<ImageToBinaryScreen> createState() => _ImageToBinaryScreenState();
}

class _ImageToBinaryScreenState extends State<ImageToBinaryScreen> {
  late final FileService _fileService;

  int _activeTab = 0; // 0 = Image -> Binary, 1 = Binary -> Image

  // --- Image -> Binary state ---
  bool _isLoadingImage = false;
  bool _isConverting = false;
  Uint8List? _selectedImageFileBytes;
  DecodedImageInfo? _decodedImage;
  BinaryPixelFormat _selectedMode = BinaryPixelFormat.rgb888;
  int _monoThreshold = 128;
  ImageBinaryConversionResult? _conversionResult;

  // Paginated preview & row selection
  static const int _bytesPerPage = 64;
  int _currentPage = 0;
  final Set<int> _selectedRowOffsets = <int>{};

  // --- Binary -> Image reconstruction state ---
  bool _isLoadingBin = false;
  bool _isLoadingMeta = false;
  bool _isReconstructing = false;
  String? _importedBinName;
  Uint8List? _importedBinBytes;
  String? _importedMetaName;
  ImageBinaryMetadata? _importedMeta;
  String? _reconstructionError;
  Uint8List? _reconstructedRgbaBytes;
  Uint8List? _reconstructedPngBytes;
  PixelComparisonMetrics? _comparisonMetrics;

  @override
  void initState() {
    super.initState();
    _fileService = widget.fileService ?? FileService.instance;
  }

  String _formatBytes(int bytes) {
    if (bytes < 0) return 'غير معروف';
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} كيلوبايت';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} ميجابايت';
  }

  String _formatInt(int value) {
    final s = value.toString();
    final sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) sb.write(',');
      sb.write(s[i]);
    }
    return sb.toString();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        backgroundColor: isError ? Colors.redAccent : null,
      ),
    );
  }

  // =========================================================================
  // Step 1: Image Selection
  // =========================================================================

  Future<void> _pickImage() async {
    if (_isLoadingImage) return;
    setState(() => _isLoadingImage = true);

    try {
      final FileSource? source = await _fileService.pickFile(
        mimeType: 'image/png,image/jpeg,image/webp',
      );
      if (source == null) return;

      final bytes = await readFileSourceBytes(source);
      final decoded = await decodeImageBytesToRgba(
        fileBytes: bytes,
        fileName: source.name,
        fileSizeBytes: source.size > 0 ? source.size : bytes.length,
      );

      if (!mounted) return;
      setState(() {
        _selectedImageFileBytes = bytes;
        _decodedImage = decoded;
        _conversionResult = null;
        _currentPage = 0;
        _selectedRowOffsets.clear();
      });
    } catch (e) {
      _showMessage('تعذر تحميل الصورة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingImage = false);
    }
  }

  // =========================================================================
  // Step 2 & 3: Convert Image to Binary
  // =========================================================================

  Future<void> _convertImage() async {
    final decoded = _decodedImage;
    if (decoded == null || _isConverting) return;

    setState(() => _isConverting = true);

    try {
      final rgba = decoded.rgbaBytes;
      final width = decoded.width;
      final height = decoded.height;
      final mode = _selectedMode;
      final threshold = _monoThreshold;
      final fileName = decoded.fileName;
      final colorMode = '${decoded.detectedFormat} • ${decoded.colorMode}';
      final hasAlpha = decoded.hasTransparentPixels;

      final result = decoded.pixelCount > 65536
          ? await Isolate.run(() {
              return convertRgbaToBinary(
                rgbaBytes: rgba,
                width: width,
                height: height,
                format: mode,
                threshold: threshold,
                sourceFileName: fileName,
                sourceColorMode: colorMode,
                sourceHadAlpha: hasAlpha,
              );
            })
          : convertRgbaToBinary(
              rgbaBytes: rgba,
              width: width,
              height: height,
              format: mode,
              threshold: threshold,
              sourceFileName: fileName,
              sourceColorMode: colorMode,
              sourceHadAlpha: hasAlpha,
            );

      if (!mounted) return;
      setState(() {
        _conversionResult = result;
        _currentPage = 0;
        _selectedRowOffsets.clear();
      });
    } catch (e) {
      _showMessage('فشل تحويل الصورة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  // =========================================================================
  // Step 4: Binary Preview Selection & Copy
  // =========================================================================

  void _toggleRowSelection(int byteOffset) {
    setState(() {
      if (_selectedRowOffsets.contains(byteOffset)) {
        _selectedRowOffsets.remove(byteOffset);
      } else {
        _selectedRowOffsets.add(byteOffset);
      }
    });
  }

  void _selectAllOnPage(BinaryPreviewPage page) {
    setState(() {
      for (final row in page.rows) {
        _selectedRowOffsets.add(row.byteOffset);
      }
    });
  }

  Future<void> _copyPageOrSelected(BinaryPreviewPage page, {required bool selectedOnly}) async {
    final rowsToCopy = selectedOnly
        ? page.rows.where((r) => _selectedRowOffsets.contains(r.byteOffset)).toList()
        : page.rows;

    if (rowsToCopy.isEmpty) {
      _showMessage('يرجى تحديد صف واحد على الأقل للنسخ.', isError: true);
      return;
    }

    final text = rowsToCopy.map((r) => r.bitsText).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage(
      selectedOnly
          ? 'تم نسخ ${rowsToCopy.length} صفاً محدداً إلى الحافظة.'
          : 'تم نسخ الصفحة الحالية (${rowsToCopy.length} صفاً) إلى الحافظة.',
    );
  }

  Future<void> _showJumpToPageDialog(int totalPages) async {
    final controller = TextEditingController(text: '${_currentPage + 1}');
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('الانتقال إلى صفحة'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '1 - $totalPages',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final val = int.tryParse(controller.text.trim());
                if (val != null && val >= 1 && val <= totalPages) {
                  Navigator.pop(ctx, val - 1);
                }
              },
              child: const Text('انتقال'),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _currentPage = selected;
        _selectedRowOffsets.clear();
      });
    }
  }

  // =========================================================================
  // Step 5: Export .bin, .meta.json, .txt
  // =========================================================================

  String _baseFileName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _exportBin() async {
    final res = _conversionResult;
    if (res == null) return;
    final base = _baseFileName(res.metadata.sourceFileName);
    final suggestedName = '${base}_${res.metadata.pixelFormat.id}.bin';

    try {
      final uri = await _fileService.createDocument(
        fileName: suggestedName,
        mimeType: 'application/octet-stream',
      );
      if (uri == null) return;

      await _fileService.writeDocumentBytes(uri, res.binaryBytes);
      _showMessage('تم تصدير الملف الثنائي (.bin) بنجاح. لا تنسَ تصدير ملف البيانات الوصفية لإعادة البناء.');
    } catch (e) {
      _showMessage('تعذر تصدير ملف .bin: $e', isError: true);
    }
  }

  Future<void> _exportMetadata() async {
    final res = _conversionResult;
    if (res == null) return;
    final base = _baseFileName(res.metadata.sourceFileName);
    final suggestedName = '${base}_${res.metadata.pixelFormat.id}.meta.json';

    try {
      final uri = await _fileService.createDocument(
        fileName: suggestedName,
        mimeType: 'application/json',
      );
      if (uri == null) return;

      final bytes = Uint8List.fromList(utf8.encode(res.metadata.toJsonString()));
      await _fileService.writeDocumentBytes(uri, bytes);
      _showMessage('تم تصدير ملف البيانات الوصفية (.meta.json) بنجاح.');
    } catch (e) {
      _showMessage('تعذر تصدير ملف البيانات الوصفية: $e', isError: true);
    }
  }

  Future<void> _exportTxt() async {
    final res = _conversionResult;
    if (res == null) return;
    if (res.totalBytes > kMaxTxtExportRawBytes) {
      _showMessage('حجم البيانات يتجاوز الحد المناسب لتصدير .txt؛ استخدم .bin بدلاً منه.', isError: true);
      return;
    }

    final base = _baseFileName(res.metadata.sourceFileName);
    final suggestedName = '${base}_${res.metadata.pixelFormat.id}_bits.txt';

    try {
      final uri = await _fileService.createDocument(
        fileName: suggestedName,
        mimeType: 'text/plain',
      );
      if (uri == null) return;

      await _fileService.writeDocumentStream(
        uri,
        streamTxtChunks(res.binaryBytes, res.metadata),
      );
      _showMessage('تم تصدير التمثيل النصي (.txt) بنجاح.');
    } catch (e) {
      _showMessage('تعذر تصدير ملف .txt: $e', isError: true);
    }
  }

  // =========================================================================
  // Binary -> Image Reconstruction
  // =========================================================================

  Future<void> _pickBinFile() async {
    if (_isLoadingBin) return;
    setState(() => _isLoadingBin = true);
    try {
      final source = await _fileService.pickFile(mimeType: '*/*');
      if (source == null) return;
      final bytes = await readFileSourceBytes(source);
      if (!mounted) return;
      setState(() {
        _importedBinName = source.name;
        _importedBinBytes = bytes;
        _reconstructionError = null;
        _reconstructedPngBytes = null;
        _reconstructedRgbaBytes = null;
        _comparisonMetrics = null;
      });
    } catch (e) {
      _showMessage('تعذر قراءة ملف .bin: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingBin = false);
    }
  }

  Future<void> _pickMetaFile() async {
    if (_isLoadingMeta) return;
    setState(() => _isLoadingMeta = true);
    try {
      final source = await _fileService.pickFile(mimeType: '*/*');
      if (source == null) return;
      final bytes = await readFileSourceBytes(source, maxBytes: 1024 * 1024);
      final meta = ImageBinaryMetadata.fromJsonString(utf8.decode(bytes));
      if (!mounted) return;
      setState(() {
        _importedMetaName = source.name;
        _importedMeta = meta;
        _reconstructionError = null;
        _reconstructedPngBytes = null;
        _reconstructedRgbaBytes = null;
        _comparisonMetrics = null;
      });
    } catch (e) {
      _showMessage('ملف البيانات الوصفية غير صالح: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingMeta = false);
    }
  }

  void _loadCurrentConversionForReconstruction() {
    final res = _conversionResult;
    if (res == null) return;
    setState(() {
      _activeTab = 1;
      _importedBinName = '${_baseFileName(res.metadata.sourceFileName)}_${res.metadata.pixelFormat.id}.bin';
      _importedBinBytes = res.binaryBytes;
      _importedMetaName = '${_baseFileName(res.metadata.sourceFileName)}_${res.metadata.pixelFormat.id}.meta.json';
      _importedMeta = res.metadata;
      _reconstructionError = null;
      _reconstructedPngBytes = null;
      _reconstructedRgbaBytes = null;
      _comparisonMetrics = null;
    });
  }

  Future<void> _reconstructImage() async {
    final binBytes = _importedBinBytes;
    final meta = _importedMeta;

    if (binBytes == null) {
      setState(() {
        _reconstructionError = 'يرجى اختيار ملف البيانات الثنائية (.bin) أولاً.';
      });
      return;
    }

    if (meta == null) {
      setState(() {
        _reconstructionError =
            'البيانات الثنائية وحدها لا تكفي لإعادة بناء الصورة. يرجى إرفاق ملف البيانات الوصفية (.meta.json) الذي يحتوي على الأبعاد وصيغة البكسل وترتيب القنوات.';
      });
      return;
    }

    setState(() {
      _isReconstructing = true;
      _reconstructionError = null;
    });

    try {
      final rgba = meta.pixelCount > 65536
          ? await Isolate.run(() {
              return reconstructBinaryToRgba(binaryData: binBytes, metadata: meta);
            })
          : reconstructBinaryToRgba(binaryData: binBytes, metadata: meta);

      final pngBytes = await encodeRgbaToPngBytes(
        rgbaBytes: rgba,
        width: meta.width,
        height: meta.height,
      );

      PixelComparisonMetrics? comparison;
      final decoded = _decodedImage;
      if (decoded != null && decoded.width == meta.width && decoded.height == meta.height) {
        final origRgba = decoded.rgbaBytes;
        final w = meta.width;
        final h = meta.height;
        comparison = meta.pixelCount > 65536
            ? await Isolate.run(() => compareRgbaBuffers(origRgba, rgba, w, h))
            : compareRgbaBuffers(origRgba, rgba, w, h);
      }

      if (!mounted) return;
      setState(() {
        _reconstructedRgbaBytes = rgba;
        _reconstructedPngBytes = pngBytes;
        _comparisonMetrics = comparison;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reconstructionError = e.toString();
        _reconstructedPngBytes = null;
        _reconstructedRgbaBytes = null;
        _comparisonMetrics = null;
      });
    } finally {
      if (mounted) setState(() => _isReconstructing = false);
    }
  }

  // =========================================================================
  // UI Building Blocks
  // =========================================================================

  Widget _buildSectionCard({
    required BuildContext context,
    required String stepNumber,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final surfaceColor = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stepNumber,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildLossBadge(BuildContext context, {required bool isLossless, String? customLabel}) {
    final color = isLossless ? const Color(0xFF059669) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        customLabel ?? (isLossless ? 'بدون فقدان (RGB)' : 'فقداني (Lossy)'),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildConvertTab(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final decoded = _decodedImage;
    final res = _conversionResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Image Selection
        _buildSectionCard(
          context: context,
          stepNumber: '1',
          title: 'اختيار الصورة (PNG / JPG / JPEG / WEBP)',
          icon: Icons.image_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: _isLoadingImage ? null : _pickImage,
                icon: _isLoadingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(decoded == null ? 'اختيار صورة من الجهاز' : 'تغيير الصورة'),
              ),
              if (decoded != null && _selectedImageFileBytes != null) ...[
                const SizedBox(height: 12),
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF020617) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    _selectedImageFileBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  decoded.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoTile(context, 'الأبعاد', '${decoded.width} × ${decoded.height}'),
                    _buildInfoTile(context, 'حجم الملف', _formatBytes(decoded.fileSizeBytes)),
                    _buildInfoTile(context, 'نظام الألوان', '${decoded.detectedFormat} • ${decoded.colorMode}'),
                    _buildInfoTile(context, 'عدد البكسلات', _formatInt(decoded.pixelCount)),
                  ],
                ),
                if (decoded.hasTransparentPixels) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ملاحظة: تحتوي الصورة على شفافية (Alpha)؛ وضع RGB الخام يحفظ قنوات R و G و B فقط (24 بت).',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),

        // 2. Choose Conversion Mode & Convert
        _buildSectionCard(
          context: context,
          stepNumber: '2',
          title: 'اختيار وضع التحويل والتحويل محلياً',
          icon: Icons.tune_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...BinaryPixelFormat.values.map((mode) {
                final selected = _selectedMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedMode = mode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: selected
                            ? theme.colorScheme.primary.withOpacity(0.10)
                            : (isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC)),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Radio<BinaryPixelFormat>(
                            value: mode,
                            groupValue: _selectedMode,
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedMode = v);
                            },
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.arabicShortLabel,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  mode == BinaryPixelFormat.rgb888
                                      ? 'يحفظ قيم قنوات R و G و B كاملة (8 بت لكل قناة)'
                                      : mode == BinaryPixelFormat.gray8
                                          ? 'يحول كل بكسل إلى قيمة إضاءة 8 بت (يفقد الألوان)'
                                          : 'يحول كل بكسل إلى 0 أو 1 حسب العتبة (يفقد الألوان والتدرجات)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildLossBadge(
                            context,
                            isLossless: mode.isLosslessRgb,
                            customLabel: mode.isLosslessRgb ? 'بدون فقدان' : 'فقداني',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (_selectedMode == BinaryPixelFormat.mono1) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('عتبة الأبيض والأسود:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_monoThreshold / 255',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _monoThreshold.toDouble(),
                  min: 0,
                  max: 255,
                  divisions: 255,
                  label: '$_monoThreshold',
                  onChanged: (v) => setState(() => _monoThreshold = v.round()),
                ),
              ],
              const SizedBox(height: 6),
              ElevatedButton.icon(
                onPressed: (decoded == null || _isConverting) ? null : _convertImage,
                icon: _isConverting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.memory_outlined),
                label: const Text('تحويل إلى بيانات ثنائية'),
              ),
            ],
          ),
        ),

        // 3. Binary Output Summary, Paginated Preview & Copy
        if (res != null) ...[
          _buildSectionCard(
            context: context,
            stepNumber: '3',
            title: 'معاينة البيانات الثنائية (0 و 1) — مقسّمة إلى صفحات',
            icon: Icons.data_array,
            child: _buildBinaryPreviewContent(context, res),
          ),

          // 4. Export Actions
          _buildSectionCard(
            context: context,
            stepNumber: '4',
            title: 'تصدير الملفات أو التحقق بإعادة البناء',
            icon: Icons.save_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _exportBin,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text('تصدير البيانات الفعلية (.bin • ${_formatBytes(res.totalBytes)})'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _exportMetadata,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('تصدير البيانات الوصفية المطلوبة (.meta.json)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: res.totalBytes <= kMaxTxtExportRawBytes ? _exportTxt : null,
                  icon: const Icon(Icons.text_snippet_outlined),
                  label: Text(
                    res.totalBytes <= kMaxTxtExportRawBytes
                        ? 'تصدير التمثيل النصي (.txt)'
                        : 'تصدير .txt غير متاح للصور الكبيرة (> 2 ميجابايت)',
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _loadCurrentConversionForReconstruction,
                  icon: const Icon(Icons.compare_outlined),
                  label: const Text('إرسال الناتج لاختبار إعادة البناء والمقارنة'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBinaryPreviewContent(BuildContext context, ImageBinaryConversionResult res) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final page = formatBinaryPage(
      res.binaryBytes,
      pageIndex: _currentPage,
      bytesPerPage: _bytesPerPage,
      bytesPerRow: 4,
      totalValidBits: res.metadata.pixelFormat == BinaryPixelFormat.mono1 ? res.totalBits : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildInfoTile(context, 'إجمالي البايتات', _formatInt(res.totalBytes)),
            _buildInfoTile(context, 'إجمالي البتات', _formatInt(res.totalBits)),
            _buildInfoTile(context, 'عمق اللون', '${res.metadata.colorDepth} بت'),
            _buildInfoTile(context, 'ترتيب القنوات', res.metadata.channelOrder),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildLossBadge(context, isLossless: res.metadata.isLossless),
            const Spacer(),
            Text(
              'صفحة ${page.pageIndex + 1} من ${page.totalPages}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Pagination & Copy Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF020617) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'الصفحة السابقة',
                    onPressed: page.pageIndex > 0
                        ? () => setState(() {
                              _currentPage = page.pageIndex - 1;
                              _selectedRowOffsets.clear();
                            })
                        : null,
                  ),
                  TextButton(
                    onPressed: page.totalPages > 1 ? () => _showJumpToPageDialog(page.totalPages) : null,
                    child: Text('${page.pageIndex + 1}/${page.totalPages}'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'الصفحة التالية',
                    onPressed: page.pageIndex + 1 < page.totalPages
                        ? () => setState(() {
                              _currentPage = page.pageIndex + 1;
                              _selectedRowOffsets.clear();
                            })
                        : null,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _selectAllOnPage(page),
                    child: const Text('تحديد الصفحة', style: TextStyle(fontSize: 12)),
                  ),
                  if (_selectedRowOffsets.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selectedRowOffsets.clear()),
                      child: const Text('مسح', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Bounded Binary Rows (LTR monospace inside RTL layout so bit offsets stay canonical)
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: page.rows.map((row) {
                  final isSelected = _selectedRowOffsets.contains(row.byteOffset);
                  return InkWell(
                    onTap: () => _toggleRowSelection(row.byteOffset),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected ? theme.colorScheme.primary.withOpacity(0.18) : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        row.formattedLine,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'اضغط على أي صف لتحديده، ثم انسخ المحدد أو الصفحة الحالية (يتم عرض $_bytesPerPage بايت فقط في كل صفحة لحماية الذاكرة).',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectedRowOffsets.isNotEmpty
                    ? () => _copyPageOrSelected(page, selectedOnly: true)
                    : null,
                icon: const Icon(Icons.copy, size: 16),
                label: Text('نسخ المحدد (${_selectedRowOffsets.length})'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copyPageOrSelected(page, selectedOnly: false),
                icon: const Icon(Icons.copy_all, size: 16),
                label: const Text('نسخ الصفحة'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReconstructTab(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = _importedMeta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionCard(
          context: context,
          stepNumber: '1',
          title: 'استيراد الملف الثنائي (.bin) والبيانات الوصفية (.meta.json)',
          icon: Icons.file_open_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _isLoadingBin ? null : _pickBinFile,
                icon: _isLoadingBin
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.attach_file),
                label: Text(
                  _importedBinName == null
                      ? 'اختيار ملف .bin'
                      : 'ملف .bin: $_importedBinName (${_formatBytes(_importedBinBytes?.length ?? 0)})',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isLoadingMeta ? null : _pickMetaFile,
                icon: _isLoadingMeta
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.data_object),
                label: Text(
                  _importedMetaName == null
                      ? 'اختيار ملف البيانات الوصفية (.meta.json)'
                      : 'البيانات الوصفية: $_importedMetaName',
                ),
              ),
              if (meta != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoTile(context, 'الأبعاد', '${meta.width} × ${meta.height}'),
                    _buildInfoTile(context, 'الصيغة', meta.pixelFormat.arabicShortLabel),
                    _buildInfoTile(context, 'عمق اللون', '${meta.colorDepth} بت'),
                    _buildInfoTile(context, 'ترتيب القنوات', meta.channelOrder),
                    if (meta.threshold != null)
                      _buildInfoTile(context, 'العتبة', '${meta.threshold}'),
                    _buildInfoTile(context, 'CRC-32', meta.crc32Hex),
                  ],
                ),
                const SizedBox(height: 8),
                _buildLossBadge(context, isLossless: meta.isLossless),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isReconstructing ? null : _reconstructImage,
                icon: _isReconstructing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_fix_high_outlined),
                label: const Text('إعادة بناء الصورة'),
              ),
              if (_reconstructionError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: Text(
                    _reconstructionError!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (_reconstructedPngBytes != null && meta != null)
          _buildSectionCard(
            context: context,
            stepNumber: '2',
            title: 'الصورة المعاد بناؤها والمقارنة',
            icon: Icons.compare,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_comparisonMetrics != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_comparisonMetrics!.isExactRgbMatch
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706))
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_comparisonMetrics!.isExactRgbMatch
                                ? const Color(0xFF059669)
                                : const Color(0xFFD97706))
                            .withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _comparisonMetrics!.isExactRgbMatch
                              ? 'تطابق تام 100% في قيم قنوات RGB (0 اختلافات — إعادة بناء بدون فقدان)'
                              : 'اختلافات متوقعة نتيجة التحويل الفقداني (${meta.pixelFormat.arabicShortLabel})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'بكسلات متطابقة: ${_formatInt(_comparisonMetrics!.identicalRgbPixels)} / ${_formatInt(_comparisonMetrics!.pixelCount)} '
                          '(${_comparisonMetrics!.exactMatchPercent.toStringAsFixed(1)}%) • أقصى فرق قناة: ${_comparisonMetrics!.maxChannelDiff}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Reconstructed image preview (and Original if loaded for direct comparison)
                if (_selectedImageFileBytes != null &&
                    _decodedImage != null &&
                    _decodedImage!.width == meta.width &&
                    _decodedImage!.height == meta.height)
                  Row(
                    children: [
                      Expanded(
                        child: _buildComparisonImageBox(
                          context,
                          title: 'الأصلية',
                          bytes: _selectedImageFileBytes!,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildComparisonImageBox(
                          context,
                          title: 'المعاد بناؤها',
                          bytes: _reconstructedPngBytes!,
                        ),
                      ),
                    ],
                  )
                else
                  _buildComparisonImageBox(
                    context,
                    title: 'الصورة المعاد بناؤها (${meta.width} × ${meta.height})',
                    bytes: _reconstructedPngBytes!,
                    height: 240,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildComparisonImageBox(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
    double height = 180,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF020617) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6.0,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحويل الصورة إلى ثنائي'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.memory_outlined, size: 18),
                        label: Text('صورة ← ثنائي'),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.restore_page_outlined, size: 18),
                        label: Text('ثنائي ← صورة'),
                      ),
                    ],
                    selected: <int>{_activeTab},
                    onSelectionChanged: (selection) {
                      setState(() => _activeTab = selection.first);
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_activeTab == 0)
                    _buildConvertTab(context)
                  else
                    _buildReconstructTab(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
