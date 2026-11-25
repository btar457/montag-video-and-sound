import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/ids.dart';
import 'package:laqta/core/media/media_library.dart';
import 'package:laqta/features/editor/editor_controller.dart';
import 'package:laqta/features/import/import_service.dart';

import '../../support/fakes.dart';

void main() {
  late Directory root;
  late Directory cache;
  late MediaLibrary library;
  late ProviderContainer container;

  EditorController editor() =>
      container.read(editorControllerProvider.notifier);
  EditorState state() => container.read(editorControllerProvider)!;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('laqta_import_test');
    cache = await Directory('${root.path}/cache').create();
    library = MediaLibrary(Directory('${root.path}/media'), movableFrom: cache);
    container = ProviderContainer.test(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          InMemoryProjectRepository(),
        ),
        idGeneratorProvider.overrideWithValue(IdGenerator(random: Random(3))),
      ],
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<String> cached(String name) async =>
      (await File('${cache.path}/$name').writeAsString('v')).path;

  ImportService service(List<String> picked, Map<String, Duration> durations) =>
      ImportService(
        picker: FakePicker(picked),
        probe: FakeProbe(durations),
        library: library,
      );

  test('imports picked videos as clips in one undo step', () async {
    editor().createNew('x');
    final a = await cached('a.mp4');
    final b = await cached('b.mp4');

    final result = await service(
      [a, b],
      {a: const Duration(seconds: 4), b: const Duration(seconds: 6)},
    ).importInto(editor());

    expect(result.added, 2);
    expect(result.failed, isEmpty);
    final clips = state().project.clips;
    expect(clips.map((c) => c.duration), [
      const Duration(seconds: 4),
      const Duration(seconds: 6),
    ]);
    expect(clips.every((c) => library.contains(c.sourcePath)), isTrue);
    expect(File(a).existsSync(), isFalse, reason: 'moved out of the cache');

    editor().undo();
    expect(state().project.clips, isEmpty, reason: 'single undo step');
  });

  test('unreadable or too-short files are reported and not kept', () async {
    editor().createNew('x');
    final good = await cached('good.mp4');
    final broken = await cached('broken.mp4');
    final tiny = await cached('tiny.mp4');

    final result = await service(
      [good, broken, tiny],
      {
        good: const Duration(seconds: 3),
        tiny: const Duration(milliseconds: 40),
      },
    ).importInto(editor());

    expect(result.added, 1);
    expect(result.failed, ['broken.mp4', 'tiny.mp4']);
    expect(state().project.clips, hasLength(1));
    expect(
      File(broken).existsSync(),
      isTrue,
      reason: 'rejected files stay put',
    );
    expect(library.directory.listSync(), hasLength(1));
  });

  test('cancelled picker changes nothing', () async {
    editor().createNew('x');
    final before = state();
    final result = await service([], {}).importInto(editor());
    expect(result.added, 0);
    expect(result.failed, isEmpty);
    expect(identical(state(), before), isTrue);
  });

  test('with no open project it fails before showing the picker', () async {
    final picker = FakePicker(['/x.mp4']);
    final s = ImportService(
      picker: picker,
      probe: FakeProbe({}),
      library: library,
    );
    await expectLater(s.importInto(editor()), throwsStateError);
    expect(picker.calls, 0);
  });

  test('100ms is accepted, 99ms is rejected', () async {
    editor().createNew('x');
    final ok = await cached('ok.mp4');
    final short = await cached('short.mp4');
    final result = await service(
      [ok, short],
      {
        ok: const Duration(milliseconds: 100),
        short: const Duration(milliseconds: 99),
      },
    ).importInto(editor());
    expect(result.added, 1);
    expect(result.failed, ['short.mp4']);
  });

  test('switching project during import adds nothing and cleans up', () async {
    final first = editor().createNew('الأول');
    final a = await cached('a.mp4');
    final s = ImportService(
      picker: FakePicker([a]),
      probe: _SwitchingProbe(() => editor().createNew('الثاني'), a),
      library: library,
    );

    await expectLater(s.importInto(editor()), throwsStateError);
    expect(state().project.name, 'الثاني');
    expect(state().project.clips, isEmpty);
    expect(first.clips, isEmpty);
    expect(
      library.directory.existsSync() ? library.directory.listSync() : [],
      isEmpty,
      reason: 'adopted file removed again',
    );
  });
}

/// Probe that opens another project mid-import, like a user leaving.
class _SwitchingProbe implements MediaProbe {
  _SwitchingProbe(this.onProbe, this.path);
  final void Function() onProbe;
  final String path;

  @override
  Future<Duration> durationOf(String p) async {
    onProbe();
    return const Duration(seconds: 2);
  }
}
