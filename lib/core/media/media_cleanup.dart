import '../storage/project_repository.dart';
import 'media_library.dart';

/// Deletes media files that no saved project uses any more (left behind by
/// undoing an import, deleting clips, or deleting a project).
///
/// Run at startup, before any project is opened: undo history lives only in
/// memory, so nothing outside saved projects can still need a file.
///
/// Conservative: if any project file is unreadable we cannot know which
/// media it uses, so nothing is deleted. Returns the number of files removed.
Future<int> cleanUnusedMedia(
  ProjectRepository projects,
  MediaLibrary library,
) async {
  final listing = await projects.list();
  if (listing.unreadable.isNotEmpty) return 0;

  final referenced = <String>{};
  for (final summary in listing.projects) {
    final project = await projects.load(summary.id);
    if (project == null) continue; // deleted meanwhile: its media is unused
    referenced.addAll(project.clips.map((c) => c.sourcePath));
  }
  return library.removeUnreferenced(referenced);
}
