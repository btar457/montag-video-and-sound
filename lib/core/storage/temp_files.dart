import 'dart:io';

/// Deletes every file directly inside [directory] (used for old export
/// renders at startup). Missing directory is fine. Sub-folders and symlink
/// targets are never touched. Returns the number of entries removed.
Future<int> clearFiles(Directory directory) async {
  if (!await directory.exists()) return 0;
  var removed = 0;
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is Directory) continue;
    try {
      await entity.delete();
      removed++;
    } on FileSystemException {
      // In use or already gone; try again next start.
    }
  }
  return removed;
}
