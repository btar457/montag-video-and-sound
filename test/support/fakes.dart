import 'dart:io';

import 'package:laqta/core/media/media_library.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/core/storage/project_repository.dart';
import 'package:laqta/features/import/import_service.dart';

/// Repository kept in memory — safe inside testWidgets (no real I/O).
class InMemoryProjectRepository extends ProjectRepository {
  InMemoryProjectRepository([List<EditProject> initial = const []])
    : super(Directory('unused')) {
    for (final p in initial) {
      projects[p.id] = p;
    }
  }

  final projects = <String, EditProject>{};
  List<String> unreadable = [];

  @override
  Future<void> save(EditProject project) async =>
      projects[project.id] = project;

  @override
  Future<EditProject?> load(String id) async => projects[id];

  @override
  Future<void> delete(String id) async => projects.remove(id);

  @override
  Future<ProjectListing> list() async => (
    projects: [
      for (final p in projects.values)
        ProjectSummary(
          id: p.id,
          name: p.name,
          clipCount: p.clips.length,
          totalDuration: p.totalDuration,
          modifiedAt: DateTime(2026),
        ),
    ],
    unreadable: unreadable,
  );
}

class FakePicker implements MediaPicker {
  FakePicker([this.paths = const []]);
  List<String> paths;
  int calls = 0;

  @override
  Future<List<String>> pickVideos() async {
    calls++;
    return paths;
  }
}

/// Durations by path; a missing path behaves like an unreadable file.
class FakeProbe implements MediaProbe {
  FakeProbe(this.durations);
  final Map<String, Duration> durations;

  @override
  Future<Duration> durationOf(String path) async {
    final d = durations[path];
    if (d == null) throw const FormatException('unreadable');
    return d;
  }
}

/// Library that "adopts" without touching the disk.
class PassThroughMediaLibrary extends MediaLibrary {
  PassThroughMediaLibrary() : super(Directory('/library'));

  @override
  Future<String> adopt(String pickedPath) async =>
      '/library/${pickedPath.split('/').last}';

  @override
  Future<void> remove(String path) async {}
}
