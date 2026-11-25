import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/export/export_request.dart';
import '../../core/format.dart';
import '../../core/project/export_aspect.dart';
import '../editor/editor_controller.dart';
import 'export_engine.dart';

/// Where finished renders go (app cache; must match ExportHandler.kt).
/// Overridden at startup in `main.dart`.
final exportDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('exportDirectoryProvider not overridden'),
);

enum _Phase { setup, running, done, failed }

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExportQuality _quality = ExportQuality.p1080;
  _Phase _phase = _Phase.setup;
  double? _fraction;
  String? _failureCode;
  StreamSubscription<ExportEvent>? _sub;
  late final ExportEngine _engine = ref.read(exportEngineProvider);

  @override
  void dispose() {
    // Leaving the screen stops the render; a half video is useless.
    if (_phase == _Phase.running) _engine.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    final project = ref.read(editorControllerProvider)!.project;
    final dir = ref.read(exportDirectoryProvider);
    final name = '${ref.read(idGeneratorProvider).next()}.mp4';
    final request = ExportRequest.fromProject(
      project,
      quality: _quality,
      outputPath: '${dir.path}${Platform.pathSeparator}$name',
    );
    setState(() {
      _phase = _Phase.running;
      _fraction = null;
    });
    _sub = _engine.start(request).listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case ExportProgress(:final fraction):
            _fraction = fraction;
          case ExportDone():
            _phase = _Phase.done;
          case ExportFailed(:final code):
            _phase = _Phase.failed;
            _failureCode = code;
          case ExportCancelled():
            _phase = _Phase.setup;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorControllerProvider);
    if (state == null || state.project.clips.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('تصدير')),
        body: const Center(child: Text('أضف مقاطع قبل التصدير')),
      );
    }
    final project = state.project;
    final (w, h) = project.aspect.sizeForShortSide(_quality.shortSide);
    final setup = _phase != _Phase.running;

    return Scaffold(
      appBar: AppBar(title: const Text('تصدير')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('المقاس', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ExportAspect>(
            segments: const [
              ButtonSegment(value: ExportAspect.portrait, label: Text('9:16')),
              ButtonSegment(value: ExportAspect.landscape, label: Text('16:9')),
              ButtonSegment(value: ExportAspect.square, label: Text('1:1')),
            ],
            selected: {project.aspect},
            onSelectionChanged: setup
                ? (s) => ref
                      .read(editorControllerProvider.notifier)
                      .setAspect(s.single)
                : null,
          ),
          const SizedBox(height: 16),
          Text('الجودة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ExportQuality>(
            segments: const [
              ButtonSegment(value: ExportQuality.p720, label: Text('720p')),
              ButtonSegment(value: ExportQuality.p1080, label: Text('1080p')),
            ],
            selected: {_quality},
            onSelectionChanged: setup
                ? (s) => setState(() => _quality = s.single)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            '${clipCountLabel(project.clips.length)} · '
            '${formatDuration(project.totalDuration)} · $w×$h',
            key: const Key('export-summary'),
          ),
          const SizedBox(height: 24),
          ..._phaseWidgets(),
        ],
      ),
    );
  }

  List<Widget> _phaseWidgets() {
    switch (_phase) {
      case _Phase.setup:
        return [
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.movie_creation_outlined),
            label: const Text('ابدأ التصدير'),
          ),
        ];
      case _Phase.running:
        final f = _fraction;
        return [
          LinearProgressIndicator(value: f),
          const SizedBox(height: 8),
          Text(
            f == null ? 'جارٍ التحضير…' : 'جارٍ التصدير ${(f * 100).round()}٪',
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _engine.cancel, child: const Text('إلغاء')),
        ];
      case _Phase.done:
        return [
          const ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('اكتمل التصدير'),
            subtitle: Text('الحفظ في المعرض يأتي في التحديث القادم'),
          ),
          OutlinedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.movie_creation_outlined),
            label: const Text('تصدير مرة أخرى'),
          ),
        ];
      case _Phase.failed:
        return [
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('تعذّر تصدير الفيديو'),
            subtitle: Text(
              _failureCode == 'busy'
                  ? 'هناك تصدير آخر قيد التنفيذ، انتظر قليلاً ثم حاول'
                  : 'تأكد من وجود مساحة كافية وحاول مرة أخرى',
            ),
          ),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.refresh),
            label: const Text('حاول مرة أخرى'),
          ),
        ];
    }
  }
}
