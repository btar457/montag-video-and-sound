import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/ids.dart';

void main() {
  test('generated ids are safe and unique', () {
    final ids = IdGenerator();
    final generated = {for (var i = 0; i < 1000; i++) ids.next()};
    expect(generated, hasLength(1000));
    expect(generated.every(isSafeId), isTrue);
  });

  test('ids are unique even with a frozen clock', () {
    final ids = IdGenerator(random: Random(1), clock: () => DateTime.utc(2026));
    expect(ids.next(), isNot(ids.next()));
  });

  test('isSafeId rejects anything that could escape a directory', () {
    for (final bad in ['', '..', '../x', 'a/b', r'a\b', 'a.json', 'x' * 65]) {
      expect(isSafeId(bad), isFalse, reason: bad);
    }
    for (final good in ['p1', 'mf3k2x9c-4h7q2z1p', 'A_b-9']) {
      expect(isSafeId(good), isTrue, reason: good);
    }
  });
}
