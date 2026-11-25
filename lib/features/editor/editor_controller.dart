import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/history/edit_history.dart';
import '../../core/ids.dart';
import '../../core/project/clip.dart';
import '../../core/project/edit_project.dart';
import '../../core/project/export_aspect.dart';
import '../../core/storage/project_repository.dart';

/// Must be overridden at startup (see `main.dart`) with a repository
/// pointing at the app's documents directory.
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => throw UnimplementedError('projectRepositoryProvider not overridden'),
);

final idGeneratorProvider = Provider<IdGenerator>((ref) => IdGenerator());

final editorControllerProvider =
    NotifierProvider<EditorController, EditorState?>(EditorController.new);

/// The open project with its undo/redo history.
class EditorState {
  const EditorState(this.history, {this.saveError});

  final EditHistory<EditProject> history;

  /// Last autosave failure, or null if the latest save succeeded.
  final Object? saveError;

  EditProject get project => history.present;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  EditorState withHistory(EditHistory<EditProject> history) =>
      EditorState(history, saveError: saveError);

  EditorState withSaveError(Object? error) =>
      EditorState(history, saveError: error);
}

/// Applies edits to the open project, keeps undo/redo history, and
/// autosaves every change. Saves run one after another, in order.
///
/// Invalid edits (e.g. splitting on a clip boundary) throw [ArgumentError]
/// and leave the state unchanged.
class EditorController extends Notifier<EditorState?> {
  Future<void> _pendingSave = Future.value();

  @override
  EditorState? build() => null;

  ProjectRepository get _repository => ref.read(projectRepositoryProvider);
  IdGenerator get _ids => ref.read(idGeneratorProvider);

  /// Opens an existing project with a fresh history.
  void open(EditProject project) {
    state = EditorState(EditHistory(project));
  }

  /// Creates, opens and saves a new empty project.
  EditProject createNew(String name) {
    final project = EditProject(id: _ids.next(), name: name);
    open(project);
    _save(project, _repository);
    return project;
  }

  void close() => state = null;

  void addClip({
    required String sourcePath,
    required Duration sourceDuration,
  }) => _apply(
    (p) => p.addClip(
      Clip.full(
        id: _ids.next(),
        sourcePath: sourcePath,
        sourceDuration: sourceDuration,
      ),
    ),
  );

  /// Adds several clips at the end as a single undo step.
  ///
  /// If [intoProjectId] is given and a different project is open now (the
  /// user switched projects during a slow import), throws [StateError] and
  /// changes nothing.
  void addClips(
    List<({String path, Duration duration})> media, {
    String? intoProjectId,
  }) {
    if (intoProjectId != null && _require().project.id != intoProjectId) {
      throw StateError('A different project was opened during the import');
    }
    if (media.isEmpty) return;
    _apply((p) {
      var next = p;
      for (final m in media) {
        next = next.addClip(
          Clip.full(
            id: _ids.next(),
            sourcePath: m.path,
            sourceDuration: m.duration,
          ),
        );
      }
      return next;
    });
  }

  void removeClip(String clipId) => _apply((p) => p.removeClip(clipId));

  void moveClip(int from, int to) => _apply((p) => p.moveClip(from, to));

  void trimClip(String clipId, {Duration? start, Duration? end}) =>
      _apply((p) => p.trimClip(clipId, start: start, end: end));

  void splitAt(Duration position) =>
      _apply((p) => p.splitAt(position, newClipId: _ids.next()));

  void setAspect(ExportAspect aspect) =>
      _apply((p) => p.copyWith(aspect: aspect));

  void rename(String name) => _apply((p) => p.copyWith(name: name));

  void undo() => _move(_require().history.undo());

  void redo() => _move(_require().history.redo());

  /// Completes when every save requested so far has finished.
  Future<void> flush() => _pendingSave;

  void _apply(EditProject Function(EditProject) edit) {
    final current = _require();
    final repository = _repository; // fails on bad setup before any change
    final next = edit(current.project); // invalid edits throw here
    if (next == current.project) return; // no-op: no undo step, no save
    state = current.withHistory(current.history.push(next));
    _save(next, repository);
  }

  void _move(EditHistory<EditProject> history) {
    final current = _require();
    if (identical(history, current.history)) return;
    final repository = _repository;
    state = current.withHistory(history);
    _save(history.present, repository);
  }

  /// Returns the open project's id; throws [StateError] if none is open.
  String requireOpen() => _require().project.id;

  EditorState _require() {
    final current = state;
    if (current == null) throw StateError('No project is open');
    return current;
  }

  void _save(EditProject project, ProjectRepository repository) {
    _pendingSave = _pendingSave.then((_) async {
      Object? error;
      try {
        await repository.save(project);
      } catch (e) {
        error = e;
      }
      if (!ref.mounted) return;
      final current = state;
      if (error == null && current?.saveError == null) return; // no change
      if (current != null && current.project.id == project.id) {
        state = current.withSaveError(error);
      }
    });
  }
}
