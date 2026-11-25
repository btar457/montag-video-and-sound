import 'dart:convert';
import 'dart:io';

import '../ids.dart';
import '../project/edit_project.dart';

/// What the home screen needs to show for one saved project.
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.clipCount,
    required this.totalDuration,
    required this.modifiedAt,
  });

  final String id;
  final String name;
  final int clipCount;
  final Duration totalDuration;
  final DateTime modifiedAt;
}

/// Result of listing saved projects. [unreadable] holds file names that
/// exist but could not be parsed; they are reported, never deleted.
typedef ProjectListing = ({
  List<ProjectSummary> projects,
  List<String> unreadable,
});

/// Saves each project as `<id>.json` inside [directory].
///
/// Writes are atomic (temp file + rename) so a crash mid-save never leaves
/// a half-written project behind.
class ProjectRepository {
  ProjectRepository(this.directory);

  static const _extension = '.json';

  final Directory directory;

  Future<void> save(EditProject project) async {
    final file = _fileFor(project.id);
    await directory.create(recursive: true);
    final temp = _tempFor(file);
    await _deleteIfPresent(temp); // never write through a stale file or link
    try {
      await temp.writeAsString(jsonEncode(project.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      await _deleteIfPresent(temp);
      rethrow;
    }
  }

  /// Returns null if no project with [id] exists.
  /// Throws [FormatException] if the file exists but is not a valid project.
  Future<EditProject?> load(String id) async {
    final file = _fileFor(id);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Project file is not a JSON object: ${file.path}');
    }
    final project = EditProject.fromJson(decoded);
    if (project.id != id) {
      throw FormatException(
        'Project id "${project.id}" does not match file name "$id"',
      );
    }
    return project;
  }

  /// All saved projects, most recently modified first.
  Future<ProjectListing> list() async {
    if (!await directory.exists()) {
      return (projects: <ProjectSummary>[], unreadable: <String>[]);
    }
    final projects = <ProjectSummary>[];
    final unreadable = <String>[];
    // followLinks: false — symlinks show up as Link and are skipped below.
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith(_extension)) continue;
      final id = name.substring(0, name.length - _extension.length);
      try {
        final project = await load(id);
        if (project == null) continue;
        projects.add(
          ProjectSummary(
            id: project.id,
            name: project.name,
            clipCount: project.clips.length,
            totalDuration: project.totalDuration,
            modifiedAt: await entity.lastModified(),
          ),
        );
      } on FormatException {
        unreadable.add(name);
      } on ArgumentError {
        unreadable.add(name); // file name is not a safe id
      } on FileSystemException {
        unreadable.add(name); // invalid UTF-8, or removed while listing
      }
    }
    projects.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    unreadable.sort();
    return (projects: projects, unreadable: unreadable);
  }

  /// Deletes the project file (and any leftover temp file).
  /// Deleting a missing project is a no-op.
  Future<void> delete(String id) async {
    final file = _fileFor(id);
    await _deleteIfPresent(file);
    await _deleteIfPresent(_tempFor(file));
  }

  File _tempFor(File file) => File('${file.path}.tmp');

  static Future<void> _deleteIfPresent(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // already gone
    }
  }

  File _fileFor(String id) {
    if (!isSafeId(id)) {
      throw ArgumentError.value(id, 'id', 'is not a safe project id');
    }
    return File('${directory.path}${Platform.pathSeparator}$id$_extension');
  }
}
