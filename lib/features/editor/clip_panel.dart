import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/project/clip.dart';
import '../../core/project/trim.dart';
import 'clip_preview.dart';
import 'editor_controller.dart';

/// Preview + trim + split for the selected clip.
class ClipPanel extends ConsumerStatefulWidget {
  const ClipPanel({super.key, required this.clip});

  final Clip clip;

  @override
  ConsumerState<ClipPanel> createState() => _ClipPanelState();
}

class _ClipPanelState extends ConsumerState<ClipPanel> {
  late final ValueNotifier<Duration> _position = ValueNotifier(
    widget.clip.trimStart,
  );

  /// Slider values while the user is dragging; null otherwise.
  RangeValues? _dragging;

  @override
  void didUpdateWidget(ClipPanel old) {
    super.didUpdateWidget(old);
    if (old.clip.id != widget.clip.id) {
      _position.value = widget.clip.trimStart;
      _dragging = null;
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  double _ms(Duration d) => d.inMilliseconds.toDouble();
  Duration _dur(double ms) => Duration(milliseconds: ms.round());

  void _commitTrim(RangeValues values) {
    final clip = widget.clip;
    final range = clampTrim(
      start: _dur(values.start),
      end: _dur(values.end),
      sourceDuration: clip.sourceDuration,
    );
    setState(() => _dragging = null);
    try {
      ref
          .read(editorControllerProvider.notifier)
          .trimClip(clip.id, start: range.start, end: range.end);
    } on ArgumentError {
      // The clip was removed (e.g. undo) while dragging; nothing to trim.
    }
  }

  bool _canSplitAt(Duration p) =>
      p - widget.clip.trimStart >= Clip.minLength &&
      widget.clip.trimEnd - p >= Clip.minLength;

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final preview = ref.watch(clipPreviewProvider);
    final values =
        _dragging ?? RangeValues(_ms(clip.trimStart), _ms(clip.trimEnd));

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            preview(clip, _position),
            // Media timelines are not mirrored in RTL (Material bidi
            // guidelines): time always runs left → right.
            Directionality(
              textDirection: TextDirection.ltr,
              child: RangeSlider(
                min: 0,
                max: _ms(clip.sourceDuration),
                values: values,
                labels: RangeLabels(
                  formatDuration(_dur(values.start)),
                  formatDuration(_dur(values.end)),
                ),
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: _commitTrim,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'من ${formatDuration(clip.trimStart)} '
                    'إلى ${formatDuration(clip.trimEnd)}',
                    key: const Key('trim-range'),
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: _position,
                  builder: (context, p, _) => FilledButton.tonalIcon(
                    onPressed: _canSplitAt(p)
                        ? () => ref
                              .read(editorControllerProvider.notifier)
                              .splitClip(clip.id, p)
                        : null,
                    icon: const Icon(Icons.content_cut),
                    label: const Text('تقسيم هنا'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
