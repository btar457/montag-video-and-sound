import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/media/media_cleanup.dart';
import 'package:laqta/core/media/media_library.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';

import '../../support/fakes.dart';

void main() {
  late Directory root;
  late MediaLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('laqta_cleanup_test');
    library = MediaLibrary(Directory('${root.path}/media'));
    await library.directory.create();
  });

  tearDown(() => root.delete(recursive: true));

  Future<String> mediaFile(String name) async =>
      (await File('${library.directory.path}/$name').writeAsString('v')).path;

  EditProject usingFile(String id, String path) =>
      EditProject(id: id, name: id).addClip(
        Clip.full(
          id: 'c',
          sourcePath: path,
          sourceDuration: const Duration(seconds: 1),
        ),
      );

  test('removes only files no saved project uses', () async {
    final used = await mediaFile('used.mp4');
    final orphan = await mediaFile('orphan.mp4');
    final repo = InMemoryProjectRepository([usingFile('p1', used)]);

    expect(await cleanUnusedMedia(repo, library), 1);
    expect(File(used).existsSync(), isTrue);
    expect(File(orphan).existsSync(), isFalse);
  });

  test('deletes nothing while any project file is unreadable', () async {
    final orphan = await mediaFile('orphan.mp4');
    final repo = InMemoryProjectRepository()..unreadable = ['bad.json'];

    expect(await cleanUnusedMedia(repo, library), 0);
    expect(File(orphan).existsSync(), isTrue);
  });
}
