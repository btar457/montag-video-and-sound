import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../import/import_service.dart';
import 'editor_controller.dart';

/// Minimal editor: clip list with reorder/delete, import, undo/redo.
/// Preview, timeline and trimming arrive in step 5.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorControllerProvider);
    if (state == null) {
      return const Scaffold(body: Center(child: Text('لا يوجد مشروع مفتوح')));
    }
    final editor = ref.read(editorControllerProvider.notifier);
    final clips = state.project.clips;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.project.name),
        actions: [
          IconButton(
            tooltip: 'تراجع',
            icon: const Icon(Icons.undo),
            onPressed: state.canUndo ? editor.undo : null,
          ),
          IconButton(
            tooltip: 'إعادة',
            icon: const Icon(Icons.redo),
            onPressed: state.canRedo ? editor.redo : null,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.video_library_outlined),
        label: const Text('إضافة فيديو'),
      ),
      body: Column(
        children: [
          if (state.saveError != null)
            ListTile(
              key: const Key('save-error'),
              tileColor: Theme.of(context).colorScheme.errorContainer,
              leading: const Icon(Icons.sync_problem),
              title: const Text(
                'تعذّر حفظ آخر تعديل. سنحاول مع التعديل القادم.',
              ),
            ),
          ListTile(
            title: Text(clipCountLabel(clips.length)),
            trailing: Text(
              formatDuration(state.project.totalDuration),
              key: const Key('total-duration'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: clips.isEmpty
                ? const Center(child: Text('أضف مقاطع فيديو من المعرض للبدء'))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: clips.length,
                    // onReorderItem already adjusts the target index for the
                    // removed item, matching moveClip's "final index".
                    onReorderItem: editor.moveClip,
                    itemBuilder: (context, i) {
                      final clip = clips[i];
                      return ListTile(
                        key: ValueKey(clip.id),
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text('مقطع ${i + 1}'),
                        subtitle: Text(formatDuration(clip.duration)),
                        trailing: IconButton(
                          tooltip: 'حذف المقطع',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => editor.removeClip(clip.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      final result = await ref
          .read(importServiceProvider)
          .importInto(ref.read(editorControllerProvider.notifier));
      if (result.failed.isNotEmpty && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'تعذّر استيراد ${result.failed.length} من الملفات: '
              '${result.failed.join('، ')}',
            ),
          ),
        );
      }
    } catch (_) {
      // If the user already left this screen, the import was cancelled on
      // purpose; no message needed.
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('تعذّر استيراد الفيديو')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
