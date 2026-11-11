import 'package:flutter/material.dart';

/// Bidirectional localization support (English LTR & Arabic RTL).
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  bool get isRtl => locale.languageCode == 'ar';
  TextDirection get textDirection => isRtl ? TextDirection.rtl : TextDirection.ltr;

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'appName': 'Magic Key',
      'tagline': 'Universal File Opener',
      'openFile': 'Open File',
      'openFileDesc': 'Select any file from device storage',
      'dropFilesHere': 'or drop files anywhere',
      'supportedCategories': 'Supported Categories',
      'recentFiles': 'Recent Files',
      'noRecentFiles': 'No recently opened files',
      'clearRecent': 'Clear History',
      // Categories
      'catDocument': 'Document',
      'catImage': 'Image',
      'catMedia': 'Audio & Video',
      'catTextCode': 'Text & Code',
      'catArchive': 'Archive',
      'catBinary': 'Binary / Other',
      // Viewer Top Bar
      'back': 'Back',
      'close': 'Close File',
      'viewInHex': 'View in Hex',
      'viewNormal': 'Standard View',
      'format': 'Format',
      'size': 'Size',
      'confidence': 'Confidence',
      'method': 'Method',
      // Text Viewer
      'lineWrap': 'Wrap Lines',
      'noWrap': 'No Wrap',
      'lineCount': 'Lines',
      'encoding': 'Encoding',
      // Hex Viewer
      'offset': 'Offset',
      'previousPage': 'Previous Page',
      'nextPage': 'Next Page',
      'pageInfo': 'Showing rows',
      'totalSize': 'Total size',
      // Unsupported / Fallback
      'unsupportedTitle': 'Unsupported Viewer Format',
      'unsupportedDesc': 'This format cannot yet be rendered natively. Displaying raw data through the Universal Hex Viewer.',
      'openHexButton': 'Inspect Raw Bytes in Hex',
      // Diagnostic & Errors
      'corruptedFile': 'Corrupted or Misnamed File',
      'corruptedDesc': 'File extension does not match content signature. Raw byte inspection recommended.',
      'errorReading': 'Error reading file stream',
      'emptyFile': 'File is empty (0 bytes)',
    },
    'ar': {
      'appName': 'المفتاح السحري',
      'tagline': 'فاتح الملفات الشامل',
      'openFile': 'فتح ملف',
      'openFileDesc': 'اختر أي ملف من ذاكرة الجهاز',
      'dropFilesHere': 'أو أسقط الملفات هنا',
      'supportedCategories': 'الأقسام المدعومة',
      'recentFiles': 'الملفات الأخيرة',
      'noRecentFiles': 'لا توجد ملفات مفتوحة مؤخراً',
      'clearRecent': 'مسح السجل',
      // Categories
      'catDocument': 'المستندات',
      'catImage': 'الصور',
      'catMedia': 'الصوت والفيديو',
      'catTextCode': 'النصوص والبرمجة',
      'catArchive': 'الأرشيف والمضغوطات',
      'catBinary': 'الملفات الثنائية',
      // Viewer Top Bar
      'back': 'رجوع',
      'close': 'إغلاق الملف',
      'viewInHex': 'عرض بنظام الست عشري',
      'viewNormal': 'العرض القياسي',
      'format': 'الصيغة',
      'size': 'الحجم',
      'confidence': 'الدقة',
      'method': 'طريقة الكشف',
      // Text Viewer
      'lineWrap': 'التفاف الأسطر',
      'noWrap': 'بدون التفاف',
      'lineCount': 'الأسطر',
      'encoding': 'الترميز',
      // Hex Viewer
      'offset': 'الإزاحة',
      'previousPage': 'الصفحة السابقة',
      'nextPage': 'الصفحة التالية',
      'pageInfo': 'عرض الصفوف',
      'totalSize': 'الحجم الإجمالي',
      // Unsupported / Fallback
      'unsupportedTitle': 'صيغة غير مدعومة للعرض المباشر',
      'unsupportedDesc': 'لا يمكن عرض هذه الصيغة بشكل رسومي حالياً. يتم عرض البايتات الخام عبر عارض الست عشري.',
      'openHexButton': 'فحص البايتات الخام عبر Hex',
      // Diagnostic & Errors
      'corruptedFile': 'ملف تالف أو غير متطابق مع امتداده',
      'corruptedDesc': 'امتداد الملف لا يطابق البصمة الفعلية لمحتواه. يوصى بفحص البايتات الخام.',
      'errorReading': 'خطأ في قراءة دفق الملف',
      'emptyFile': 'الملف فارغ (0 بايت)',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
