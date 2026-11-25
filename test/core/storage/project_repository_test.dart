import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/core/project/export_aspect.dart';
import 'package:laqta/core/storage/project_repository.dart';

EditProject sample(String id, {String name = 'مشروع', int clips = 1}) {
  var p = EditProject(id: id, name: name, aspect: ExportAspect.landscape);
  for (var i = 0; i < clips; i++) {
    p = p.addClip(
      Clip.full(
        id: 'c$i',
        sourcePath: '/v/$i.mp4',
        sourceDuration: const Duration(seconds: 5),
      ),
    );
  }
  return p;
}

void main() {
  late Directory root;
  late Directory dir;
  late ProjectRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('laqta_repo_test');
    dir = Directory('${root.path}/projects'); // does not exist yet
    repo = ProjectRepository(dir);
  });

  tearDown(() => root.delete(recursive: true));

  test('save then load returns the same project', () async {
    final project = sample('p1', clips: 2);
    await repo.save(project);
    final loaded = await repo.load('p1');
    expect(loaded, isNotNull);
    expect(loaded!.toJson(), project.toJson());
  });

  test('save creates the directory and leaves no temp file', () async {
    await repo.save(sample('p1'));
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, ['p1.json']);
  });

  test('saving again overwrites the previous version', () async {
    await repo.save(sample('p1', name: 'قديم'));
    await repo.save(sample('p1', name: 'جديد', clips: 3));
    final loaded = await repo.load('p1');
    expect(loaded!.name, 'جديد');
    expect(loaded.clips, hasLength(3));
  });

  test('load returns null for a missing project', () async {
    expect(await repo.load('nope'), isNull);
  });

  test('unsafe ids are rejected for every operation', () async {
    expect(() => repo.load('../etc/passwd'), throwsArgumentError);
    expect(() => repo.delete('a/b'), throwsArgumentError);
    expect(
      () => repo.save(EditProject(id: '../escape', name: 'x')),
      throwsArgumentError,
    );
  });

  test('load throws FormatException for corrupt files', () async {
    await dir.create(recursive: true);
    await File('${dir.path}/bad.json').writeAsString('{not json');
    await File('${dir.path}/arr.json').writeAsString('[1, 2]');
    expect(() => repo.load('bad'), throwsFormatException);
    expect(() => repo.load('arr'), throwsFormatException);
  });

  test('load rejects a file whose content id differs from its name', () async {
    await repo.save(sample('p1'));
    await File('${dir.path}/p1.json').rename('${dir.path}/p2.json');
    expect(() => repo.load('p2'), throwsFormatException);
  });

  test('list on a missing directory is empty', () async {
    final listing = await repo.list();
    expect(listing.projects, isEmpty);
    expect(listing.unreadable, isEmpty);
  });

  test('list returns summaries, newest first, and reports bad files', () async {
    await repo.save(sample('old', name: 'أقدم', clips: 1));
    await repo.save(sample('new', name: 'أحدث', clips: 2));
    await File('${dir.path}/old.json')
        .setLastModified(DateTime.now().subtract(const Duration(days: 1)));
    await File('${dir.path}/broken.json').writeAsString('oops');
    await File('${dir.path}/notes.txt').writeAsString('ignored');

    final listing = await repo.list();
    expect(listing.projects.map((p) => p.id), ['new', 'old']);
    expect(listing.projects.first.name, 'أحدث');
    expect(listing.projects.first.clipCount, 2);
    expect(listing.projects.first.totalDuration, const Duration(seconds: 10));
    expect(listing.unreadable, ['broken.json']);
    expect(File('${dir.path}/broken.json').existsSync(), isTrue);
  });

  test('a file with invalid UTF-8 is reported, not fatal', () async {
    await repo.save(sample('good'));
    await File('${dir.path}/garbled.json').writeAsBytes([0xff, 0xfe, 0x00]);
    final listing = await repo.list();
    expect(listing.projects.map((p) => p.id), ['good']);
    expect(listing.unreadable, ['garbled.json']);
  });

  test('symlinks in the projects directory are ignored', () async {
    final outside = File('${root.path}/outside.json');
    await outside.writeAsString('{}');
    await dir.create(recursive: true);
    await Link('${dir.path}/linked.json').create(outside.path);
    final listing = await repo.list();
    expect(listing.projects, isEmpty);
    expect(listing.unreadable, isEmpty);
  });

  test(
    'save replaces a stale temp link instead of writing through it',
    () async {
      final victim = File('${root.path}/victim.txt');
      await victim.writeAsString('original');
      await dir.create(recursive: true);
      await Link('${dir.path}/p1.json.tmp').create(victim.path);
      await repo.save(sample('p1'));
      expect(await victim.readAsString(), 'original');
      expect((await repo.load('p1'))!.id, 'p1');
      expect(File('${dir.path}/p1.json.tmp').existsSync(), isFalse);
    },
  );

  test('delete also removes a leftover temp file', () async {
    await repo.save(sample('p1'));
    await File('${dir.path}/p1.json.tmp').writeAsString('partial');
    await repo.delete('p1');
    expect(dir.listSync(), isEmpty);
  });

  test('delete removes the project and ignores missing ones', () async {
    await repo.save(sample('p1'));
    await repo.delete('p1');
    expect(await repo.load('p1'), isNull);
    await repo.delete('p1');
  });
}
