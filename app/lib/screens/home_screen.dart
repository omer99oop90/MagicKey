import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';
import '../models/file_source.dart';
import '../services/file_service.dart';
import '../services/recent_files_service.dart';
import '../widgets/category_grid.dart';
import 'viewer_screen.dart';

/// Minimalist, hyper-focused Home Screen for Magic Key.
class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final Function(Locale) onLocaleChange;
  final Locale currentLocale;

  const HomeScreen({
    super.key,
    required this.onToggleTheme,
    required this.onLocaleChange,
    required this.currentLocale,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FileService _fileService = FileService();
  final RecentFilesService _recentService = RecentFilesService.instance;
  bool _isOpening = false;

  @override
  void initState() {
    super.initState();
    _checkInitialIntent();
  }

  Future<void> _checkInitialIntent() async {
    final incomingFile = await _fileService.checkInitialIntent();
    if (incomingFile != null && mounted) {
      _openFile(incomingFile);
    }
  }

  Future<void> _handleOpenFile() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    try {
      final fileSource = await _fileService.pickFile();
      if (fileSource != null && mounted) {
        await _openFile(fileSource);
      }
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  Future<void> _openFile(FileSource fileSource) async {
    // 1. Identify format via Rust core detection engine
    final detection = await _fileService.identifyFile(fileSource);

    // 2. Add to recent files locally
    _recentService.add(fileSource);

    // 3. Navigate to Universal Viewer Screen
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ViewerScreen(
            fileSource: fileSource,
            detectionResult: detection,
          ),
        ),
      );
      // Refresh recents on return
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isArabic = widget.currentLocale.languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/branding/magic-key.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                theme.colorScheme.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.get('appName'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Language Switcher Toggle
          TextButton(
            onPressed: () {
              final next = isArabic ? const Locale('en') : const Locale('ar');
              widget.onLocaleChange(next);
            },
            child: Text(
              isArabic ? 'English' : 'العربية',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          // Theme Mode Switcher
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            tooltip: 'Toggle Theme',
            onPressed: widget.onToggleTheme,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                const SizedBox(height: 16),

                // Hero Branding Section
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: SvgPicture.asset(
                      'assets/branding/magic-key.svg',
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    l10n.get('appName'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    l10n.get('tagline'),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Prominent Open File Action Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isOpening ? null : _handleOpenFile,
                    icon: _isOpening
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.folder_open_outlined, size: 22),
                    label: Text(
                      l10n.get('openFile'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    l10n.get('openFileDesc'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // Supported Categories Section
                Row(
                  children: [
                    Text(
                      l10n.get('supportedCategories'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const CategoryGrid(),
                const SizedBox(height: 32),

                // Recent Files Section
                if (_recentService.entries.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        l10n.get('recentFiles'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _recentService.clear()),
                        child: Text(
                          l10n.get('clearRecent'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recentService.entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = _recentService.entries[index];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        tileColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                        leading: Icon(
                          Icons.history,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          entry.toSource().formattedSize,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _openFile(entry.toSource()),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
