import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/storage/temp_files.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('laqta_tmp'));
  tearDown(() => root.delete(recursive: true));

  test('deletes files, keeps sub-folders and symlink targets', () async {
    final exports = await Directory('${root.path}/exports').create();
    await File('${exports.path}/a.mp4').writeAsString('x');
    await File('${exports.path}/b.mp4').writeAsString('y');
    final sub = await Directory('${exports.path}/sub').create();
    final target = await File('${root.path}/keep.mp4').writeAsString('k');
    await Link('${exports.path}/l.mp4').create(target.path);

    expect(await clearFiles(exports), 3);
    expect(exports.listSync().map((e) => e.path), [sub.path]);
    expect(target.existsSync(), isTrue);
  });

  test('missing directory is fine', () async {
    expect(await clearFiles(Directory('${root.path}/nope')), 0);
  });
}
