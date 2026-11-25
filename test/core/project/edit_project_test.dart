import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/core/project/export_aspect.dart';

Clip clip(String id, int seconds) => Clip.full(
  id: id,
  sourcePath: '/v/$id.mp4',
  sourceDuration: Duration(seconds: seconds),
);

void main() {
  late EditProject project;

  setUp(() {
    project = EditProject(
      id: 'p1',
      name: 'تجربة',
    ).addClip(clip('a', 4)).addClip(clip('b', 6)).addClip(clip('c', 2));
  });

  test('new project defaults to 9:16 and is empty', () {
    final empty = EditProject(id: 'p', name: 'x');
    expect(empty.aspect, ExportAspect.portrait);
    expect(empty.clips, isEmpty);
    expect(empty.totalDuration, Duration.zero);
  });

  test('value equality compares every field and clip order', () {
    final copy = EditProject.fromJson(project.toJson());
    expect(copy, project);
    expect(copy.hashCode, project.hashCode);
    expect(project.copyWith(name: 'آخر'), isNot(project));
    expect(project.moveClip(0, 1), isNot(project));
    expect(project.copyWith(aspect: ExportAspect.square), isNot(project));
  });

  test('totalDuration sums clip durations', () {
    expect(project.totalDuration, const Duration(seconds: 12));
  });

  test('edits return a new project and leave the original untouched', () {
    final edited = project.removeClip('b');
    expect(edited.clips.map((c) => c.id), ['a', 'c']);
    expect(project.clips.map((c) => c.id), ['a', 'b', 'c']);
    expect(() => project.clips.add(clip('d', 1)), throwsUnsupportedError);
  });

  test('rejects duplicate clip ids', () {
    expect(() => project.addClip(clip('a', 1)), throwsArgumentError);
  });

  test('removeClip with unknown id throws', () {
    expect(() => project.removeClip('zzz'), throwsArgumentError);
  });

  test('trimClip with unknown id throws', () {
    expect(
      () => project.trimClip('zzz', start: Duration.zero),
      throwsArgumentError,
    );
  });

  test('moveClip reorders clips', () {
    expect(project.moveClip(0, 2).clips.map((c) => c.id), ['b', 'c', 'a']);
    expect(project.moveClip(2, 0).clips.map((c) => c.id), ['c', 'a', 'b']);
    expect(() => project.moveClip(0, 3), throwsRangeError);
    expect(() => project.moveClip(-1, 0), throwsRangeError);
  });

  test('trimClip updates only the target clip', () {
    final edited = project.trimClip('b', start: const Duration(seconds: 1));
    expect(edited.clips[1].duration, const Duration(seconds: 5));
    expect(edited.clips[0], project.clips[0]);
    expect(edited.totalDuration, const Duration(seconds: 11));
  });

  group('locate', () {
    test('finds clip and offset', () {
      expect(project.locate(Duration.zero), (index: 0, offset: Duration.zero));
      expect(project.locate(const Duration(seconds: 5)), (
        index: 1,
        offset: const Duration(seconds: 1),
      ));
    });

    test('boundary belongs to the next clip', () {
      expect(project.locate(const Duration(seconds: 4)), (
        index: 1,
        offset: Duration.zero,
      ));
    });

    test('returns null on an empty project', () {
      expect(EditProject(id: 'p', name: 'x').locate(Duration.zero), isNull);
    });

    test('returns null outside the timeline', () {
      expect(project.locate(const Duration(seconds: -1)), isNull);
      expect(project.locate(const Duration(seconds: 12)), isNull);
    });
  });

  test('splitClip cuts at a source-file time', () {
    final trimmed = project.trimClip('b', start: const Duration(seconds: 1));
    // b now uses source 1s..6s; cut at source 4s → 3s + 2s.
    final edited = trimmed.splitClip(
      'b',
      const Duration(seconds: 4),
      newClipId: 'b2',
    );
    expect(edited.clips.map((c) => c.id), ['a', 'b', 'b2', 'c']);
    expect(edited.clips[1].trimStart, const Duration(seconds: 1));
    expect(edited.clips[1].trimEnd, const Duration(seconds: 4));
    expect(edited.clips[2].trimStart, const Duration(seconds: 4));
    expect(edited.clips[2].trimEnd, const Duration(seconds: 6));
    expect(edited.totalDuration, trimmed.totalDuration);
  });

  test('splitClip boundaries: exactly 100ms is allowed, 99ms is not', () {
    final trimmed = project.trimClip('b', start: const Duration(seconds: 1));
    const ms = Duration(milliseconds: 1);
    final start = trimmed.clips[1].trimStart;
    final end = trimmed.clips[1].trimEnd;
    expect(
      trimmed.splitClip('b', start + ms * 100, newClipId: 'x').clips,
      hasLength(4),
    );
    expect(
      trimmed.splitClip('b', end - ms * 100, newClipId: 'x').clips,
      hasLength(4),
    );
    expect(
      () => trimmed.splitClip('b', start + ms * 99, newClipId: 'x'),
      throwsArgumentError,
    );
    expect(
      () => trimmed.splitClip('b', end - ms * 99, newClipId: 'x'),
      throwsArgumentError,
    );
  });

  test('splitClip outside the used range or unknown clip throws', () {
    final trimmed = project.trimClip('b', start: const Duration(seconds: 1));
    expect(
      () => trimmed.splitClip('b', Duration.zero, newClipId: 'x'),
      throwsArgumentError,
    );
    expect(
      () =>
          trimmed.splitClip('zzz', const Duration(seconds: 2), newClipId: 'x'),
      throwsArgumentError,
    );
  });

  test('splitAt splits the clip under the playhead', () {
    final edited = project.splitAt(const Duration(seconds: 7), newClipId: 'b2');
    expect(edited.clips.map((c) => c.id), ['a', 'b', 'b2', 'c']);
    expect(edited.clips[1].duration, const Duration(seconds: 3));
    expect(edited.clips[2].duration, const Duration(seconds: 3));
    expect(edited.totalDuration, project.totalDuration);
  });

  test('splitAt on a boundary or outside the timeline throws', () {
    expect(
      () => project.splitAt(const Duration(seconds: 4), newClipId: 'x'),
      throwsArgumentError,
    );
    expect(
      () => project.splitAt(const Duration(seconds: 20), newClipId: 'x'),
      throwsArgumentError,
    );
  });

  test('JSON round trip through a string keeps the project', () {
    final edited = project
        .copyWith(aspect: ExportAspect.square)
        .trimClip('a', end: const Duration(seconds: 3));
    final decoded = EditProject.fromJson(
      jsonDecode(jsonEncode(edited.toJson())) as Map<String, Object?>,
    );
    expect(decoded.toJson(), edited.toJson());
    expect(decoded.name, 'تجربة');
    expect(decoded.aspect, ExportAspect.square);
  });

  group('fromJson rejects malformed input with FormatException', () {
    test('missing field', () {
      final json = project.toJson()..remove('name');
      expect(() => EditProject.fromJson(json), throwsFormatException);
    });

    test('wrong type', () {
      final json = project.toJson()..['clips'] = 'not a list';
      expect(() => EditProject.fromJson(json), throwsFormatException);
    });

    test('unknown aspect', () {
      final json = project.toJson()..['aspect'] = 'cinema';
      expect(() => EditProject.fromJson(json), throwsFormatException);
    });

    test('invalid clip (trim beyond source)', () {
      final json = project.toJson();
      final clips = json['clips']! as List<Object?>;
      (clips.first! as Map<String, Object?>)['trimEndUs'] = 999999999;
      expect(() => EditProject.fromJson(json), throwsFormatException);
    });
  });

  test('fromJson rejects unknown schema versions', () {
    final json = project.toJson()..['schemaVersion'] = 99;
    expect(() => EditProject.fromJson(json), throwsFormatException);
  });
}
