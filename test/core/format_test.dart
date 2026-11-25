import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/format.dart';

void main() {
  test('formats minutes and seconds', () {
    expect(formatDuration(Duration.zero), '0:00');
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
    expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
  });

  test('adds hours from one hour', () {
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  test('rounds down partial seconds and clamps negatives', () {
    expect(formatDuration(const Duration(milliseconds: 1999)), '0:01');
    expect(formatDuration(const Duration(seconds: -3)), '0:00');
  });

  test('clip counts use correct Arabic number agreement', () {
    expect(clipCountLabel(0), 'لا مقاطع');
    expect(clipCountLabel(1), 'مقطع واحد');
    expect(clipCountLabel(2), 'مقطعان');
    expect(clipCountLabel(3), '3 مقاطع');
    expect(clipCountLabel(10), '10 مقاطع');
    expect(clipCountLabel(11), '11 مقطعاً');
    expect(clipCountLabel(99), '99 مقطعاً');
    expect(clipCountLabel(100), '100 مقطع');
    expect(clipCountLabel(103), '103 مقاطع');
  });
}
