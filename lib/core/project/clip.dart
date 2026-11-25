/// A single piece of source media placed on the timeline.
///
/// A clip never modifies its source file; it only records which part of the
/// source (`trimStart`..`trimEnd`) is used. Instances are immutable.
class Clip {
  /// Shortest clip the editor allows, to avoid zero-length or unplayable parts.
  static const Duration minLength = Duration(milliseconds: 100);

  Clip({
    required this.id,
    required this.sourcePath,
    required this.sourceDuration,
    required this.trimStart,
    required this.trimEnd,
  }) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'must not be empty');
    if (sourcePath.isEmpty) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'must not be empty');
    }
    if (trimStart.isNegative) {
      throw ArgumentError.value(trimStart, 'trimStart', 'must not be negative');
    }
    if (trimEnd > sourceDuration) {
      throw ArgumentError.value(
        trimEnd,
        'trimEnd',
        'must not exceed sourceDuration ($sourceDuration)',
      );
    }
    if (trimEnd - trimStart < minLength) {
      throw ArgumentError(
        'Clip must be at least $minLength long '
        '(got ${trimEnd - trimStart}).',
      );
    }
  }

  /// A clip that uses the whole source.
  factory Clip.full({
    required String id,
    required String sourcePath,
    required Duration sourceDuration,
  }) => Clip(
    id: id,
    sourcePath: sourcePath,
    sourceDuration: sourceDuration,
    trimStart: Duration.zero,
    trimEnd: sourceDuration,
  );

  final String id;
  final String sourcePath;
  final Duration sourceDuration;
  final Duration trimStart;
  final Duration trimEnd;

  /// Length of this clip on the timeline.
  Duration get duration => trimEnd - trimStart;

  /// Returns a copy using a different part of the source.
  Clip trimmed({Duration? start, Duration? end}) => Clip(
    id: id,
    sourcePath: sourcePath,
    sourceDuration: sourceDuration,
    trimStart: start ?? trimStart,
    trimEnd: end ?? trimEnd,
  );

  /// Splits this clip at [offset], measured from the clip's own start.
  ///
  /// The first part keeps this clip's [id]; the second gets [newId].
  /// Both parts must be at least [minLength] long.
  (Clip, Clip) splitAt(Duration offset, {required String newId}) {
    if (newId == id) {
      throw ArgumentError.value(newId, 'newId', 'must differ from the clip id');
    }
    if (offset < minLength || duration - offset < minLength) {
      throw ArgumentError.value(
        offset,
        'offset',
        'each part must be at least $minLength long',
      );
    }
    final cut = trimStart + offset;
    return (
      trimmed(end: cut),
      Clip(
        id: newId,
        sourcePath: sourcePath,
        sourceDuration: sourceDuration,
        trimStart: cut,
        trimEnd: trimEnd,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'sourcePath': sourcePath,
    'sourceDurationUs': sourceDuration.inMicroseconds,
    'trimStartUs': trimStart.inMicroseconds,
    'trimEndUs': trimEnd.inMicroseconds,
  };

  factory Clip.fromJson(Map<String, Object?> json) => Clip(
    id: json['id']! as String,
    sourcePath: json['sourcePath']! as String,
    sourceDuration: Duration(microseconds: json['sourceDurationUs']! as int),
    trimStart: Duration(microseconds: json['trimStartUs']! as int),
    trimEnd: Duration(microseconds: json['trimEndUs']! as int),
  );

  @override
  bool operator ==(Object other) =>
      other is Clip &&
      other.id == id &&
      other.sourcePath == sourcePath &&
      other.sourceDuration == sourceDuration &&
      other.trimStart == trimStart &&
      other.trimEnd == trimEnd;

  @override
  int get hashCode =>
      Object.hash(id, sourcePath, sourceDuration, trimStart, trimEnd);

  @override
  // sourcePath is left out on purpose: it reveals the user's file names and
  // must not end up in logs or crash reports.
  String toString() =>
      'Clip($id, ${trimStart.inMilliseconds}ms..${trimEnd.inMilliseconds}ms)';
}
