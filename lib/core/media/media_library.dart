import 'dart:io';

import '../ids.dart';

/// App-private, permanent home for imported media files.
///
/// The Android picker hands us copies inside the app *cache*, which the OS
/// may clear at any time. [adopt] moves them here so projects keep working.
class MediaLibrary {
  /// [movableFrom] is the only directory files may be *moved* out of
  /// (the picker's cache). Anything else is copied, never moved, so a
  /// user's original file is never taken away from where it was.
  MediaLibrary(this.directory, {this._movableFrom, IdGenerator? ids})
    : _ids = ids ?? IdGenerator();

  final Directory directory;
  final Directory? _movableFrom;
  final IdGenerator _ids;

  static final RegExp _extension = RegExp(r'\.([A-Za-z0-9]{1,5})$');

  /// Brings [pickedPath] into the library and returns its new path.
  ///
  /// Files inside `movableFrom` are renamed (instant, no extra space), with
  /// copy + delete as fallback across file systems. Other files are copied.
  /// The new name is generated: nothing of the original name is kept.
  Future<String> adopt(String pickedPath) async {
    final source = File(pickedPath);
    if (!await source.exists()) {
      throw FileSystemException('Picked file does not exist', pickedPath);
    }
    await directory.create(recursive: true);
    final ext = _extension.firstMatch(pickedPath)?.group(1)?.toLowerCase();
    final target = File(
      '${_clean(directory.path)}${Platform.pathSeparator}${_ids.next()}'
      '${ext == null ? '' : '.$ext'}',
    );
    final movable = _movableFrom;
    final mayMove = movable != null && _isUnder(pickedPath, movable.path);

    if (mayMove) {
      try {
        await source.rename(target.path);
        return target.path;
      } on FileSystemException {
        // Different file system: fall through to copy, then delete below.
      }
    }
    try {
      await source.copy(target.path);
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
    if (mayMove) {
      try {
        await source.delete();
      } on FileSystemException {
        // A leftover cache copy is harmless; the OS clears the cache.
      }
    }
    return target.path;
  }

  /// Whether [path] names an entry directly inside this library.
  ///
  /// Strict on purpose: only absolute paths without `.`/`..` segments are
  /// accepted, so no spelling of a path can point outside the library.
  bool contains(String path) {
    if (!_isPlainAbsolute(path)) return false;
    final parent = File(_clean(path)).parent.path;
    return parent == _clean(directory.path);
  }

  /// Deletes a library file. Refuses paths outside the library so a bad
  /// project file can never make us delete the user's own media.
  Future<void> remove(String path) async {
    if (!contains(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'is not inside the media library',
      );
    }
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.file:
      case FileSystemEntityType.link: // deletes the link, never its target
        await File(path).delete();
      default:
        throw ArgumentError.value(path, 'path', 'is not a file');
    }
  }

  /// Deletes every library file whose path is not in [referenced].
  /// Returns how many were deleted.
  Future<int> removeUnreferenced(Set<String> referenced) async {
    if (!await directory.exists()) return 0;
    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) continue;
      if (referenced.contains(entity.path)) continue;
      await remove(entity.path);
      removed++;
    }
    return removed;
  }

  static String _clean(String path) {
    var p = path;
    while (p.length > 1 && p.endsWith(Platform.pathSeparator)) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static bool _isPlainAbsolute(String path) {
    if (!File(path).isAbsolute) return false;
    final segments = path.split(Platform.pathSeparator);
    return !segments.any((s) => s == '.' || s == '..');
  }

  static bool _isUnder(String path, String dir) =>
      _isPlainAbsolute(path) &&
      _isPlainAbsolute(dir) &&
      _clean(path).startsWith('${_clean(dir)}${Platform.pathSeparator}');
}
