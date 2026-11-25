/// Formats a duration as `m:ss`, or `h:mm:ss` from one hour.
/// Rounds down to whole seconds; negative durations count as zero.
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// Arabic count of clips with correct number agreement:
/// 0 → لا مقاطع، 1 → مقطع واحد، 2 → مقطعان، 3–10 → "3 مقاطع"، 11–99 → "11 مقطعاً".
String clipCountLabel(int n) {
  if (n <= 0) return 'لا مقاطع';
  if (n == 1) return 'مقطع واحد';
  if (n == 2) return 'مقطعان';
  final hundreds = n % 100;
  if (hundreds >= 3 && hundreds <= 10) return '$n مقاطع';
  if (hundreds >= 11) return '$n مقطعاً';
  return '$n مقطع'; // 100, 101, 102, 200…
}
