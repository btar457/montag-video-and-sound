import 'clip.dart';

/// Turns a raw trim range (e.g. from a range slider) into a valid one:
/// inside `0..sourceDuration`, start before end, and at least [minLength]
/// long. When the range is too short it grows its end, or its start if the
/// end is already at the end of the source.
({Duration start, Duration end}) clampTrim({
  required Duration start,
  required Duration end,
  required Duration sourceDuration,
  Duration minLength = Clip.minLength,
}) {
  if (sourceDuration < minLength) {
    throw ArgumentError.value(
      sourceDuration,
      'sourceDuration',
      'is shorter than the minimum clip length',
    );
  }
  Duration clamp(Duration d) =>
      d.isNegative ? Duration.zero : (d > sourceDuration ? sourceDuration : d);

  var s = clamp(start);
  var e = clamp(end);
  if (e < s) (s, e) = (e, s);
  if (e - s < minLength) {
    e = s + minLength;
    if (e > sourceDuration) {
      e = sourceDuration;
      s = sourceDuration - minLength;
    }
  }
  return (start: s, end: e);
}
