import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/trim.dart';

void main() {
  const ten = Duration(seconds: 10);
  Duration ms(int v) => Duration(milliseconds: v);

  test('a valid range is returned unchanged', () {
    expect(clampTrim(start: ms(1000), end: ms(4000), sourceDuration: ten), (
      start: ms(1000),
      end: ms(4000),
    ));
  });

  test('values outside the source are clamped', () {
    expect(clampTrim(start: ms(-500), end: ms(12000), sourceDuration: ten), (
      start: Duration.zero,
      end: ten,
    ));
  });

  test('reversed range is swapped', () {
    expect(clampTrim(start: ms(5000), end: ms(2000), sourceDuration: ten), (
      start: ms(2000),
      end: ms(5000),
    ));
  });

  test('too-short range grows its end', () {
    expect(clampTrim(start: ms(3000), end: ms(3020), sourceDuration: ten), (
      start: ms(3000),
      end: ms(3100),
    ));
  });

  test('too-short range at the very end grows its start instead', () {
    expect(clampTrim(start: ms(9980), end: ten, sourceDuration: ten), (
      start: ms(9900),
      end: ten,
    ));
  });

  test('rejects sources shorter than the minimum', () {
    expect(
      () => clampTrim(start: ms(0), end: ms(50), sourceDuration: ms(50)),
      throwsArgumentError,
    );
  });
}
