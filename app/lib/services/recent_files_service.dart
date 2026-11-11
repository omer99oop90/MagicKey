import '../models/file_source.dart';

/// Lightweight entry for a recently viewed file.
class RecentFileEntry {
  final String name;
  final String? path;
  final String? uri;
  final int size;
  final DateTime openedAt;

  const RecentFileEntry({
    required this.name,
    this.path,
    this.uri,
    required this.size,
    required this.openedAt,
  });

  FileSource toSource() {
    if (uri != null) {
      return AndroidUriFileSource(uri: uri!, name: name, size: size);
    }
    return LocalPathFileSource(path: path ?? '', name: name, size: size);
  }
}

/// Service managing recent files list locally in memory without external database overhead.
class RecentFilesService {
  static final RecentFilesService instance = RecentFilesService._();
  RecentFilesService._();

  final List<RecentFileEntry> _entries = [];
  static const int maxEntries = 10;

  List<RecentFileEntry> get entries => List.unmodifiable(_entries);

  void add(FileSource source) {
    _entries.removeWhere((e) =>
        (source.uri != null && e.uri == source.uri) ||
        (source.path != null && e.path == source.path));

    _entries.insert(
      0,
      RecentFileEntry(
        name: source.name,
        path: source.path,
        uri: source.uri,
        size: source.size,
        openedAt: DateTime.now(),
      ),
    );

    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  void clear() {
    _entries.clear();
  }
}
