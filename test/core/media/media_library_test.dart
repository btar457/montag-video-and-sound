import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/media/media_library.dart';

void main() {
  late Directory root;
  late Directory cache;
  late MediaLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('laqta_media_test');
    cache = await Directory('${root.path}/cache/picker-uuid')
        .create(recursive: true);
    library = MediaLibrary(
      Directory('${root.path}/media'),
      movableFrom: Directory('${root.path}/cache'),
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> picked(String name, [String content = 'video-bytes']) =>
      File('${cache.path}/$name').writeAsString(content);

  test('adopt moves the file out of the cache into the library', () async {
    final source = await picked('رحلة العيد.MP4');
    final path = await library.adopt(source.path);

    expect(source.existsSync(), isFalse, reason: 'moved, not duplicated');
    expect(await File(path).readAsString(), 'video-bytes');
    expect(library.contains(path), isTrue);
  });

  test('new name is generated; only a lower-cased extension is kept', () async {
    final path = await library.adopt((await picked('رحلة العيد.MP4')).path);
    final name = path.split(Platform.pathSeparator).last;
    expect(name, matches(RegExp(r'^[a-z0-9-]+\.mp4$')));
  });

  test('odd or missing extensions are dropped', () async {
    final a = await library.adopt((await picked('noext')).path);
    final b = await library.adopt((await picked('x.verylongext')).path);
    expect(a.split(Platform.pathSeparator).last, isNot(contains('.')));
    expect(b.split(Platform.pathSeparator).last, isNot(contains('.')));
  });

  test('two adopts never collide', () async {
    final a = await library.adopt((await picked('a.mp4')).path);
    final b = await library.adopt((await picked('a.mp4', 'other')).path);
    expect(a, isNot(b));
    expect(await File(b).readAsString(), 'other');
  });

  test('adopting a missing file throws', () async {
    expect(
      () => library.adopt('${cache.path}/gone.mp4'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('remove deletes library files and refuses anything outside', () async {
    final path = await library.adopt((await picked('a.mp4')).path);
    await library.remove(path);
    expect(File(path).existsSync(), isFalse);
    await library.remove(path); // already gone: no error

    final userFile = await picked('keep.mp4');
    expect(() => library.remove(userFile.path), throwsArgumentError);
    expect(
      () => library.remove('${library.directory.path}/../cache/keep.mp4'),
      throwsArgumentError,
    );
    expect(userFile.existsSync(), isTrue);
  });

  test('files outside the cache are copied, never moved', () async {
    final original = await File('${root.path}/my-video.mp4')
        .writeAsString('orig');
    final path = await library.adopt(original.path);
    expect(original.existsSync(), isTrue, reason: "user's file stays put");
    expect(await File(path).readAsString(), 'orig');
  });

  test('a cache path with .. is not treated as movable', () async {
    final original = await File('${root.path}/outside.mp4').writeAsString('o');
    await library.adopt('${root.path}/cache/../outside.mp4');
    expect(original.existsSync(), isTrue);
  });

  test('contains rejects every non-plain spelling of a path', () {
    final dir = library.directory.path;
    for (final bad in [
      '$dir/..',
      '$dir/.',
      '$dir/./x.mp4',
      '$dir/sub/../x.mp4',
      '$dir/../cache/x.mp4',
      'media/x.mp4',
      '${root.path}/x.mp4',
    ]) {
      expect(library.contains(bad), isFalse, reason: bad);
    }
    expect(library.contains('$dir/x.mp4'), isTrue);
  });

  test('remove deletes a symlink itself, never its target', () async {
    final target = await picked('target.mp4');
    await library.directory.create(recursive: true);
    final link = await Link('${library.directory.path}/l.mp4')
        .create(target.path);
    await library.remove(link.path);
    expect(Link(link.path).existsSync(), isFalse);
    expect(target.existsSync(), isTrue);
  });

  test('remove refuses a directory inside the library', () async {
    final sub = await Directory('${library.directory.path}/sub')
        .create(recursive: true);
    expect(() => library.remove(sub.path), throwsArgumentError);
    expect(sub.existsSync(), isTrue);
  });

  test('removeUnreferenced keeps referenced files only', () async {
    final keep = await library.adopt((await picked('a.mp4')).path);
    final drop = await library.adopt((await picked('b.mp4')).path);
    final removed = await library.removeUnreferenced({keep});
    expect(removed, 1);
    expect(File(keep).existsSync(), isTrue);
    expect(File(drop).existsSync(), isFalse);
  });

  test('removeUnreferenced on a missing library does nothing', () async {
    expect(await library.removeUnreferenced({}), 0);
  });
}
