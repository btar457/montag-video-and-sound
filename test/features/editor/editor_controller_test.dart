import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/ids.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/core/project/export_aspect.dart';
import 'package:laqta/core/storage/project_repository.dart';
import 'package:laqta/features/editor/editor_controller.dart';

void main() {
  late Directory root;
  late ProjectRepository repo;
  late ProviderContainer container;

  EditorController controller() =>
      container.read(editorControllerProvider.notifier);
  EditorState state() => container.read(editorControllerProvider)!;

  ProviderContainer makeContainer(ProjectRepository repository) =>
      ProviderContainer.test(
        overrides: [
          projectRepositoryProvider.overrideWithValue(repository),
          idGeneratorProvider.overrideWithValue(IdGenerator(random: Random(7))),
        ],
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('laqta_editor_test');
    repo = ProjectRepository(Directory('${root.path}/projects'));
    container = makeContainer(repo);
  });

  tearDown(() => root.delete(recursive: true));

  void addTwoClips() {
    controller()
      ..addClip(
        sourcePath: '/v/a.mp4',
        sourceDuration: const Duration(seconds: 4),
      )
      ..addClip(
        sourcePath: '/v/b.mp4',
        sourceDuration: const Duration(seconds: 6),
      );
  }

  test('nothing is open initially, and edits require an open project', () {
    expect(container.read(editorControllerProvider), isNull);
    expect(controller().undo, throwsStateError);
  });

  test('createNew opens and saves an empty project', () async {
    final project = controller().createNew('رحلتي');
    expect(state().project.name, 'رحلتي');
    expect(state().canUndo, isFalse);
    await controller().flush();
    final saved = await repo.load(project.id);
    expect(saved!.name, 'رحلتي');
  });

  test('every edit is autosaved; the file matches the latest state', () async {
    final project = controller().createNew('x');
    addTwoClips();
    controller().splitAt(const Duration(seconds: 6));
    controller().setAspect(ExportAspect.square);
    await controller().flush();

    final saved = await repo.load(project.id);
    expect(saved!.toJson(), state().project.toJson());
    expect(saved.clips, hasLength(3));
    expect(saved.aspect, ExportAspect.square);
  });

  test('undo and redo restore snapshots and are saved too', () async {
    final project = controller().createNew('x');
    addTwoClips();
    controller().removeClip(state().project.clips.first.id);
    expect(state().project.clips, hasLength(1));

    controller().undo();
    expect(state().project.clips, hasLength(2));
    expect(state().canRedo, isTrue);
    await controller().flush();
    expect((await repo.load(project.id))!.clips, hasLength(2));

    controller().redo();
    expect(state().project.clips, hasLength(1));
    await controller().flush();
    expect((await repo.load(project.id))!.clips, hasLength(1));
  });

  test('a new edit after undo clears redo', () {
    controller().createNew('x');
    addTwoClips();
    controller().undo();
    controller().rename('y');
    expect(state().canRedo, isFalse);
    expect(state().project.name, 'y');
  });

  test('invalid edit throws and leaves state and history unchanged', () {
    controller().createNew('x');
    addTwoClips();
    final before = state();
    expect(
      () => controller().splitAt(const Duration(seconds: 4)), // on a boundary
      throwsArgumentError,
    );
    expect(identical(state(), before), isTrue);
  });

  test('trimClip and moveClip go through history', () {
    controller().createNew('x');
    addTwoClips();
    final firstId = state().project.clips.first.id;
    controller().trimClip(firstId, end: const Duration(seconds: 1));
    controller().moveClip(0, 1);
    expect(state().project.clips.last.id, firstId);
    expect(state().project.totalDuration, const Duration(seconds: 7));
    controller().undo();
    controller().undo();
    expect(state().project.totalDuration, const Duration(seconds: 10));
  });

  test('a failed save is reported, then cleared by the next success', () async {
    final flaky = _ScriptedRepository()..failNext = true;
    final c = makeContainer(flaky);
    final editor = c.read(editorControllerProvider.notifier);

    editor.createNew('x');
    await editor.flush();
    expect(
      c.read(editorControllerProvider)!.saveError,
      isA<FileSystemException>(),
    );

    editor.rename('y'); // same container, repository now succeeds
    await editor.flush();
    expect(c.read(editorControllerProvider)!.saveError, isNull);
    expect(flaky.saved.last.name, 'y');
  });

  test('saves run strictly in order even if the first one is slow', () async {
    final slow = _ScriptedRepository()..holdFirst = true;
    final c = makeContainer(slow);
    final editor = c.read(editorControllerProvider.notifier);

    editor.createNew('v1');
    editor.rename('v2');
    editor.rename('v3');
    await Future<void>.delayed(Duration.zero);
    expect(slow.started, 1, reason: 'second save must wait for the first');

    slow.release();
    await editor.flush();
    expect(slow.saved.map((p) => p.name), ['v1', 'v2', 'v3']);
  });

  test('edits that change nothing add no undo step and no save', () async {
    final spy = _ScriptedRepository();
    final c = makeContainer(spy);
    final editor = c.read(editorControllerProvider.notifier);

    editor.createNew('x');
    editor.addClip(
      sourcePath: '/v/a.mp4',
      sourceDuration: const Duration(seconds: 3),
    );
    await editor.flush();
    final before = c.read(editorControllerProvider)!;
    final savesBefore = spy.saved.length;

    editor
      ..rename('x')
      ..setAspect(before.project.aspect)
      ..moveClip(0, 0);
    await editor.flush();

    expect(identical(c.read(editorControllerProvider), before), isTrue);
    expect(spy.saved.length, savesBefore);
  });

  test('addClips: empty list is a no-op; wrong project is refused', () {
    final p = controller().createNew('x');
    final before = state();
    controller().addClips([]);
    expect(identical(state(), before), isTrue);

    final media = [(path: '/m/a.mp4', duration: const Duration(seconds: 2))];
    expect(
      () => controller().addClips(media, intoProjectId: 'other'),
      throwsStateError,
    );
    expect(state().project.clips, isEmpty);

    controller().addClips(media, intoProjectId: p.id);
    expect(state().project.clips, hasLength(1));
  });

  test('close clears the open project', () {
    controller().createNew('x');
    controller().close();
    expect(container.read(editorControllerProvider), isNull);
  });
}

/// In-memory repository whose saves can be made to fail or to stall.
class _ScriptedRepository extends ProjectRepository {
  _ScriptedRepository() : super(Directory('unused'));

  final saved = <EditProject>[];
  bool failNext = false;
  bool holdFirst = false;
  int started = 0;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> save(EditProject project) async {
    started++;
    if (holdFirst && started == 1) await _gate.future;
    if (failNext) {
      failNext = false;
      throw const FileSystemException('disk full');
    }
    saved.add(project);
  }
}
