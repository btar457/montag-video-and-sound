import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/media_library.dart';
import '../../core/project/clip.dart';
import '../editor/editor_controller.dart';

/// Lets the user choose videos. Returns local file paths (empty if cancelled).
abstract interface class MediaPicker {
  Future<List<String>> pickVideos();
}

/// Reads a video's duration without decoding it fully.
abstract interface class MediaProbe {
  Future<Duration> durationOf(String path);
}

/// Uses the system photo picker on Android 13+ (and its backport below),
/// which needs no storage permission.
class ImagePickerMediaPicker implements MediaPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<List<String>> pickVideos() async {
    final files = await _picker.pickMultiVideo();
    return [for (final f in files) f.path];
  }
}

class VideoPlayerMediaProbe implements MediaProbe {
  /// A damaged file can make the player hang; treat that as unreadable.
  static const timeout = Duration(seconds: 10);

  @override
  Future<Duration> durationOf(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize().timeout(timeout);
      return controller.value.duration;
    } finally {
      await controller.dispose();
    }
  }
}

/// Must be overridden at startup (see `main.dart`).
final mediaLibraryProvider = Provider<MediaLibrary>(
  (ref) => throw UnimplementedError('mediaLibraryProvider not overridden'),
);
final mediaPickerProvider = Provider<MediaPicker>(
  (ref) => ImagePickerMediaPicker(),
);
final mediaProbeProvider = Provider<MediaProbe>(
  (ref) => VideoPlayerMediaProbe(),
);
final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    picker: ref.watch(mediaPickerProvider),
    probe: ref.watch(mediaProbeProvider),
    library: ref.watch(mediaLibraryProvider),
  ),
);

/// Outcome of one import. [failed] holds file names (not full paths).
typedef ImportResult = ({int added, List<String> failed});

/// Picks videos, checks they are readable, moves them into the media
/// library, and adds them to the open project as one undoable step.
class ImportService {
  ImportService({
    required this._picker,
    required this._probe,
    required this._library,
  });

  final MediaPicker _picker;
  final MediaProbe _probe;
  final MediaLibrary _library;

  Future<ImportResult> importInto(EditorController editor) async {
    // Fail before showing the picker, and remember which project we import
    // into: the user may leave and open another one while we work.
    final projectId = editor.requireOpen();
    final picked = await _picker.pickVideos();
    final accepted = <({String path, Duration duration})>[];
    final failed = <String>[];

    for (final path in picked) {
      try {
        final duration = await _probe.durationOf(path);
        if (duration < Clip.minLength) {
          throw const FormatException('Video is too short or unreadable');
        }
        accepted.add((path: await _library.adopt(path), duration: duration));
      } catch (_) {
        failed.add(path.split(Platform.pathSeparator).last);
      }
    }

    if (accepted.isNotEmpty) {
      try {
        editor.addClips(accepted, intoProjectId: projectId);
      } catch (_) {
        for (final a in accepted) {
          try {
            await _library.remove(a.path); // don't leave orphan files
          } catch (_) {
            // Startup cleanup removes anything left behind.
          }
        }
        rethrow;
      }
    }
    return (added: accepted.length, failed: failed);
  }
}
