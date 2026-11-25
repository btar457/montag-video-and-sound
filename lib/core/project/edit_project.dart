import 'clip.dart';
import 'export_aspect.dart';

/// Where a timeline position falls: which clip, and how far into it.
typedef TimelineLocation = ({int index, Duration offset});

/// An editing project: an ordered list of clips and export settings.
///
/// Immutable — every edit returns a new project. This is the document that
/// is saved to disk as JSON and handed to the render engine on export.
class EditProject {
  static const int schemaVersion = 1;

  EditProject({
    required this.id,
    required this.name,
    this.aspect = ExportAspect.portrait,
    List<Clip> clips = const [],
  }) : clips = List.unmodifiable(clips) {
    final ids = <String>{};
    for (final clip in this.clips) {
      if (!ids.add(clip.id)) {
        throw ArgumentError('Duplicate clip id: ${clip.id}');
      }
    }
  }

  final String id;
  final String name;
  final ExportAspect aspect;
  final List<Clip> clips;

  Duration get totalDuration =>
      clips.fold(Duration.zero, (sum, clip) => sum + clip.duration);

  EditProject copyWith({
    String? name,
    ExportAspect? aspect,
    List<Clip>? clips,
  }) => EditProject(
    id: id,
    name: name ?? this.name,
    aspect: aspect ?? this.aspect,
    clips: clips ?? this.clips,
  );

  EditProject addClip(Clip clip) => copyWith(clips: [...clips, clip]);

  EditProject removeClip(String clipId) {
    _indexOf(clipId);
    return copyWith(clips: clips.where((c) => c.id != clipId).toList());
  }

  /// Moves the clip at [from] so that it ends up at index [to].
  EditProject moveClip(int from, int to) {
    RangeError.checkValidIndex(from, clips, 'from');
    RangeError.checkValidIndex(to, clips, 'to');
    final reordered = [...clips];
    final clip = reordered.removeAt(from);
    reordered.insert(to, clip);
    return copyWith(clips: reordered);
  }

  EditProject trimClip(String clipId, {Duration? start, Duration? end}) {
    final index = _indexOf(clipId);
    final updated = [...clips];
    updated[index] = clips[index].trimmed(start: start, end: end);
    return copyWith(clips: updated);
  }

  /// Splits clip [clipId] at [sourcePosition], a time in its *source* file
  /// (what the preview player reports), not on the timeline.
  EditProject splitClip(
    String clipId,
    Duration sourcePosition, {
    required String newClipId,
  }) {
    final index = _indexOf(clipId);
    final clip = clips[index];
    final (first, second) = clip.splitAt(
      sourcePosition - clip.trimStart,
      newId: newClipId,
    );
    final updated = [...clips]..replaceRange(index, index + 1, [first, second]);
    return copyWith(clips: updated);
  }

  /// Splits whichever clip is under the timeline [position].
  EditProject splitAt(Duration position, {required String newClipId}) {
    final location = locate(position);
    if (location == null) {
      throw ArgumentError.value(
        position,
        'position',
        'is outside the timeline',
      );
    }
    final (first, second) = clips[location.index].splitAt(
      location.offset,
      newId: newClipId,
    );
    final updated = [...clips]
      ..replaceRange(location.index, location.index + 1, [first, second]);
    return copyWith(clips: updated);
  }

  /// Finds the clip playing at timeline [position].
  ///
  /// A position exactly on a boundary belongs to the following clip.
  /// Returns null for negative positions or positions at/after the end.
  TimelineLocation? locate(Duration position) {
    if (position.isNegative) return null;
    var start = Duration.zero;
    for (var i = 0; i < clips.length; i++) {
      final end = start + clips[i].duration;
      if (position < end) return (index: i, offset: position - start);
      start = end;
    }
    return null;
  }

  int _indexOf(String clipId) {
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1) {
      throw ArgumentError.value(clipId, 'clipId', 'no such clip');
    }
    return index;
  }

  /// Value equality: same id, name, aspect and clips in the same order.
  @override
  bool operator ==(Object other) {
    if (other is! EditProject ||
        other.id != id ||
        other.name != name ||
        other.aspect != aspect ||
        other.clips.length != clips.length) {
      return false;
    }
    for (var i = 0; i < clips.length; i++) {
      if (other.clips[i] != clips[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, name, aspect, Object.hashAll(clips));

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'aspect': aspect.name,
    'clips': [for (final clip in clips) clip.toJson()],
  };

  /// Parses a saved project.
  ///
  /// Any malformed input (wrong schema version, missing field, wrong type,
  /// invalid clip) throws a [FormatException], so callers loading files from
  /// disk only need to handle one error type.
  factory EditProject.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported project schemaVersion: $version');
    }
    try {
      return EditProject(
        id: json['id']! as String,
        name: json['name']! as String,
        aspect: ExportAspect.values.byName(json['aspect']! as String),
        clips: [
          for (final clip in json['clips']! as List<Object?>)
            Clip.fromJson(clip! as Map<String, Object?>),
        ],
      );
    } on TypeError catch (e) {
      throw FormatException('Malformed project JSON: $e');
    } on ArgumentError catch (e) {
      throw FormatException('Invalid project JSON: ${e.message}');
    }
  }
}
