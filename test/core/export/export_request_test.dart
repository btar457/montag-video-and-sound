import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/export/export_request.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/core/project/export_aspect.dart';

void main() {
  final project =
      EditProject(id: 'p', name: 'x', aspect: ExportAspect.landscape)
          .addClip(
            Clip.full(
              id: 'a',
              sourcePath: '/media/a.mp4',
              sourceDuration: const Duration(seconds: 10),
            ),
          )
          .addClip(
            Clip.full(
              id: 'b',
              sourcePath: '/media/b.mp4',
              sourceDuration: const Duration(seconds: 6),
            ),
          )
          .trimClip(
            'a',
            start: const Duration(milliseconds: 1500),
            end: const Duration(seconds: 4),
          );

  test('carries size, clip order and trims in microseconds', () {
    final r = ExportRequest.fromProject(
      project,
      quality: ExportQuality.p720,
      outputPath: '/cache/exports/out.mp4',
    );
    expect(r.toMap(), {
      'outputPath': '/cache/exports/out.mp4',
      'width': 1280,
      'height': 720,
      'clips': [
        {'path': '/media/a.mp4', 'startUs': 1500000, 'endUs': 4000000},
        {'path': '/media/b.mp4', 'startUs': 0, 'endUs': 6000000},
      ],
    });
    expect(r.totalDuration, const Duration(milliseconds: 8500));
    expect(r.totalDuration, project.totalDuration);
  });

  test('clip list cannot be modified after building', () {
    final r = ExportRequest.fromProject(
      project,
      quality: ExportQuality.p720,
      outputPath: '/o.mp4',
    );
    expect(
      () => r.clips.add((path: '/x', startUs: 0, endUs: 1)),
      throwsUnsupportedError,
    );
  });

  test('1080p portrait is 1080x1920', () {
    final r = ExportRequest.fromProject(
      project.copyWith(aspect: ExportAspect.portrait),
      quality: ExportQuality.p1080,
      outputPath: '/o.mp4',
    );
    expect((r.width, r.height), (1080, 1920));
  });

  test('an empty project cannot be exported', () {
    expect(
      () => ExportRequest.fromProject(
        EditProject(id: 'e', name: 'e'),
        quality: ExportQuality.p720,
        outputPath: '/o.mp4',
      ),
      throwsArgumentError,
    );
  });
}
