import '../project/edit_project.dart';

/// Output quality, by the short side of the frame in pixels.
enum ExportQuality {
  p720(720),
  p1080(1080);

  const ExportQuality(this.shortSide);
  final int shortSide;
}

/// Everything the native engine needs to render one video.
///
/// Deliberately flat and primitive (ints and strings) so it crosses the
/// platform channel unchanged and the Kotlin side can validate every field.
class ExportRequest {
  ExportRequest._({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.clips,
  });

  /// Builds the request for [project]. Throws [ArgumentError] for an empty
  /// project, since there is nothing to render.
  factory ExportRequest.fromProject(
    EditProject project, {
    required ExportQuality quality,
    required String outputPath,
  }) {
    if (project.clips.isEmpty) {
      throw ArgumentError.value(project.id, 'project', 'has no clips');
    }
    final (width, height) = project.aspect.sizeForShortSide(quality.shortSide);
    return ExportRequest._(
      outputPath: outputPath,
      width: width,
      height: height,
      clips: List.unmodifiable([
        for (final c in project.clips)
          (
            path: c.sourcePath,
            startUs: c.trimStart.inMicroseconds,
            endUs: c.trimEnd.inMicroseconds,
          ),
      ]),
    );
  }

  final String outputPath;
  final int width;
  final int height;
  final List<({String path, int startUs, int endUs})> clips;

  Duration get totalDuration => clips.fold(
    Duration.zero,
    (sum, c) => sum + Duration(microseconds: c.endUs - c.startUs),
  );

  Map<String, Object?> toMap() => {
    'outputPath': outputPath,
    'width': width,
    'height': height,
    'clips': [
      for (final c in clips)
        {'path': c.path, 'startUs': c.startUs, 'endUs': c.endUs},
    ],
  };
}
