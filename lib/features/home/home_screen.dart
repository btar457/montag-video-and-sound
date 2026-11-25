import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/storage/project_repository.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_screen.dart';

final projectListProvider = FutureProvider.autoDispose<ProjectListing>(
  (ref) => ref.watch(projectRepositoryProvider).list(),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Guards against double taps opening two editors / creating two projects.
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(projectListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('لقطة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _guarded(() async {
          ref.read(editorControllerProvider.notifier).createNew('مشروع جديد');
          await _openEditor();
        }),
        icon: const Icon(Icons.add),
        label: const Text('مشروع جديد'),
      ),
      body: listing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _Message(
          icon: Icons.error_outline,
          title: 'تعذّر تحميل المشاريع',
          subtitle: 'أعد فتح التطبيق، وإن تكرر الأمر أخبرنا',
        ),
        data: (data) => data.projects.isEmpty
            ? const _Message(
                icon: Icons.movie_creation_outlined,
                title: 'لا توجد مشاريع بعد',
                subtitle: 'ابدأ مشروعك الأول بقصّ ودمج مقاطعك',
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final p in data.projects)
                    ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(p.name),
                      subtitle: Text(
                        '${clipCountLabel(p.clipCount)} · ${formatDuration(p.totalDuration)}',
                      ),
                      onTap: () => _guarded(() => _openSaved(p.id)),
                    ),
                  if (data.unreadable.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(
                        'ملفات مشاريع تالفة لا يمكن فتحها: '
                        '${data.unreadable.length}',
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_opening) return;
    _opening = true;
    try {
      await action();
    } finally {
      _opening = false;
    }
  }

  Future<void> _openSaved(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final project = await ref.read(projectRepositoryProvider).load(id);
      if (project == null) throw const FormatException('missing');
      ref.read(editorControllerProvider.notifier).open(project);
      if (mounted) await _openEditor();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر فتح المشروع')),
      );
      ref.invalidate(projectListProvider);
    }
  }

  Future<void> _openEditor() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const EditorScreen()));
    await ref.read(editorControllerProvider.notifier).flush();
    ref.read(editorControllerProvider.notifier).close();
    ref.invalidate(projectListProvider);
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(subtitle, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
