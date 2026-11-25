import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/clip.dart';

void main() {
  const tenSeconds = Duration(seconds: 10);
  Clip full() =>
      Clip.full(id: 'a', sourcePath: '/v/a.mp4', sourceDuration: tenSeconds);

  group('Clip', () {
    test('full clip spans the whole source', () {
      final clip = full();
      expect(clip.trimStart, Duration.zero);
      expect(clip.trimEnd, tenSeconds);
      expect(clip.duration, tenSeconds);
    });

    test('trimmed changes the used range and duration', () {
      final clip = full().trimmed(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 5),
      );
      expect(clip.duration, const Duration(seconds: 3));
      expect(clip.id, 'a');
    });

    test('rejects invalid trims', () {
      expect(
        () => full().trimmed(start: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => full().trimmed(end: const Duration(seconds: 11)),
        throwsArgumentError,
      );
      expect(
        () => full().trimmed(
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 4),
        ),
        throwsArgumentError,
      );
      expect(
        () => full().trimmed(end: const Duration(milliseconds: 50)),
        throwsArgumentError,
      );
    });

    test('rejects empty id or source path', () {
      expect(
        () => Clip.full(
          id: '',
          sourcePath: '/v/a.mp4',
          sourceDuration: tenSeconds,
        ),
        throwsArgumentError,
      );
      expect(
        () => Clip.full(id: 'a', sourcePath: '', sourceDuration: tenSeconds),
        throwsArgumentError,
      );
    });

    test('splitAt produces two contiguous parts covering the original', () {
      final clip = full().trimmed(start: const Duration(seconds: 1));
      final (first, second) = clip.splitAt(
        const Duration(seconds: 3),
        newId: 'b',
      );
      expect(first.id, 'a');
      expect(second.id, 'b');
      expect(first.trimStart, const Duration(seconds: 1));
      expect(first.trimEnd, const Duration(seconds: 4));
      expect(second.trimStart, const Duration(seconds: 4));
      expect(second.trimEnd, tenSeconds);
      expect(first.duration + second.duration, clip.duration);
    });

    test('splitAt rejects cuts that leave a part too short', () {
      expect(
        () => full().splitAt(const Duration(milliseconds: 50), newId: 'b'),
        throwsArgumentError,
      );
      expect(
        () => full().splitAt(
          tenSeconds - const Duration(milliseconds: 50),
          newId: 'b',
        ),
        throwsArgumentError,
      );
      expect(
        () => full().splitAt(const Duration(seconds: 5), newId: 'a'),
        throwsArgumentError,
      );
    });

    test('JSON round trip keeps every field', () {
      final clip = full().trimmed(
        start: const Duration(milliseconds: 1234),
        end: const Duration(milliseconds: 5678),
      );
      expect(Clip.fromJson(clip.toJson()), clip);
    });
  });
}
