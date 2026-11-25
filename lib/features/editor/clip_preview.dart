import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/project/clip.dart';

/// Builds the preview for one clip. [position] must be kept up to date with
/// the playback position in the clip's *source* file.
typedef ClipPreviewBuilder = Widget Function(
  Clip clip,
  ValueNotifier<Duration> position,
);

/// Swapped for a fake in widget tests (video_player needs a real device).
final clipPreviewProvider = Provider<ClipPreviewBuilder>(
  (ref) =>
      (clip, position) => VideoClipPreview(
        key: ValueKey(clip.sourcePath),
        clip: clip,
        position: position,
      ),
);

/// Plays only the trimmed part of a clip: starts at `trimStart`, stops at
/// `trimEnd`.
class VideoClipPreview extends StatefulWidget {
  const VideoClipPreview({
    super.key,
    required this.clip,
    required this.position,
  });

  final Clip clip;
  final ValueNotifier<Duration> position;

  @override
  State<VideoClipPreview> createState() => _VideoClipPreviewState();
}

class _VideoClipPreviewState extends State<VideoClipPreview> {
  /// "Close enough to the end" when deciding to restart from trimStart.
  static const _endSlack = Duration(milliseconds: 50);

  VideoPlayerController? _controller;
  bool _failed = false;

  /// Fires exactly at trimEnd; player position updates only every ~100ms.
  Timer? _stopTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(File(widget.clip.sourcePath));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return; // disposed while loading
      await controller.seekTo(widget.clip.trimStart);
      if (!mounted) return;
      controller.addListener(_onTick);
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(VideoClipPreview old) {
    super.didUpdateWidget(old);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final clip = widget.clip;
    final pos = controller.value.position;
    // Another clip from the same file, or the trim moved past the playhead.
    if (old.clip.id != clip.id || pos < clip.trimStart || pos > clip.trimEnd) {
      _stopTimer?.cancel();
      controller.pause();
      controller.seekTo(clip.trimStart);
      widget.position.value = clip.trimStart;
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    widget.position.value = value.position;
    if (value.isPlaying && value.position >= widget.clip.trimEnd) _stopAtEnd();
    if (mounted) setState(() {}); // refresh play/pause icon
  }

  void _stopAtEnd() {
    _stopTimer?.cancel();
    final controller = _controller;
    if (controller == null || !mounted) return;
    controller.pause();
    controller.seekTo(widget.clip.trimEnd);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      _stopTimer?.cancel();
      await controller.pause();
      return;
    }
    if (controller.value.position >= widget.clip.trimEnd - _endSlack) {
      await controller.seekTo(widget.clip.trimStart);
    }
    await controller.play();
    final remaining = widget.clip.trimEnd - controller.value.position;
    _stopTimer?.cancel();
    _stopTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _stopAtEnd,
    );
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('تعذّر تشغيل المقطع')),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final value = controller.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          // At most a third of the screen, so the panel fits in landscape.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height / 3,
          ),
          child: AspectRatio(
            aspectRatio: value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: value.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: _togglePlay,
            ),
            Text(formatDuration(value.position - widget.clip.trimStart)),
            const Text(' / '),
            Text(formatDuration(widget.clip.duration)),
          ],
        ),
      ],
    );
  }
}
