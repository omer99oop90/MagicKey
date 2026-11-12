import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/app_localizations.dart';

class CategoryItem {
  final String id;
  final String titleKey;
  final String fallbackTitle;
  final String iconPath;
  final String formatsHint;
  final String mimeType;

  const CategoryItem({
    required this.id,
    required this.titleKey,
    required this.fallbackTitle,
    required this.iconPath,
    required this.formatsHint,
    this.mimeType = '*/*',
  });
}

/// Minimal visual grid representing supported file categories with Lucide SVG icons.
class CategoryGrid extends StatelessWidget {
  final ValueChanged<CategoryItem>? onCategorySelected;

  const CategoryGrid({
    super.key,
    this.onCategorySelected,
  });

  static const List<CategoryItem> categories = [
    CategoryItem(
      id: 'document',
      titleKey: 'catDocument',
      fallbackTitle: 'Document',
      iconPath: 'assets/icons/file-text.svg',
      formatsHint: 'Plain Text (PDF: Raw Hex)',
      mimeType: '*/*',
    ),
    CategoryItem(
      id: 'image',
      titleKey: 'catImage',
      fallbackTitle: 'Image',
      iconPath: 'assets/icons/image.svg',
      formatsHint: 'PNG, JPEG, WebP, SVG, GIF',
      mimeType: 'image/*',
    ),
    CategoryItem(
      id: 'media',
      titleKey: 'catMedia',
      fallbackTitle: 'Audio & Video',
      iconPath: 'assets/icons/film.svg',
      formatsHint: 'Audio & Video (Raw Hex / Phase 3)',
      mimeType: 'audio/*, video/*',
    ),
    CategoryItem(
      id: 'text_code',
      titleKey: 'catTextCode',
      fallbackTitle: 'Text & Code',
      iconPath: 'assets/icons/code.svg',
      formatsHint: 'Source Code, JSON, XML, MD',
      mimeType: 'text/*',
    ),
    CategoryItem(
      id: 'archive',
      titleKey: 'catArchive',
      fallbackTitle: 'Archive',
      iconPath: 'assets/icons/archive.svg',
      formatsHint: 'ZIP, APK, TAR (Raw Hex / Phase 3)',
      mimeType: '*/*',
    ),
    CategoryItem(
      id: 'binary',
      titleKey: 'catBinary',
      fallbackTitle: 'Binary & Other',
      iconPath: 'assets/icons/binary.svg',
      formatsHint: 'Hex Engine, Byte Inspection',
      mimeType: '*/*',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 3 ? 2.6 : 2.2,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            final localizedTitle = l10n.get(cat.titleKey);
            final displayTitle = localizedTitle.isNotEmpty ? localizedTitle : cat.fallbackTitle;

            return Material(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onCategorySelected != null ? () => onCategorySelected!(cat) : null,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SvgPicture.asset(
                          cat.iconPath,
                          colorFilter: ColorFilter.mode(
                            theme.colorScheme.primary,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cat.formatsHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
