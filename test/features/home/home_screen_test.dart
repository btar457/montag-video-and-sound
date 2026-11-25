import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/features/editor/editor_controller.dart';
import 'package:laqta/features/import/import_service.dart';
import 'package:laqta/main.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fakes.dart';

void main() {
  late InMemoryProjectRepository repo;
  late FakePicker picker;

  Widget app() => ProviderScope(
    overrides: [
      projectRepositoryProvider.overrideWithValue(repo),
      mediaLibraryProvider.overrideWithValue(PassThroughMediaLibrary()),
      mediaPickerProvider.overrideWithValue(picker),
      mediaProbeProvider.overrideWithValue(
        FakeProbe({
          '/cache/a.mp4': const Duration(seconds: 4),
          '/cache/b.mp4': const Duration(seconds: 65),
        }),
      ),
    ],
    child: const LaqtaApp(),
  );

  setUp(() {
    repo = InMemoryProjectRepository();
    picker = FakePicker(['/cache/a.mp4', '/cache/b.mp4']);
  });

  testWidgets('lists saved projects with clip count and duration', (t) async {
    repo = InMemoryProjectRepository([
      EditProject(id: 'p1', name: 'رحلة البصرة').addClip(
        Clip.full(
          id: 'c1',
          sourcePath: '/library/a.mp4',
          sourceDuration: const Duration(seconds: 90),
        ),
      ),
    ]);
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    expect(find.text('رحلة البصرة'), findsOneWidget);
    expect(find.text('مقطع واحد · 1:30'), findsOneWidget);
  });

  testWidgets('reports unreadable project files', (t) async {
    repo.unreadable = ['bad.json'];
    repo.projects['p1'] = EditProject(id: 'p1', name: 'x');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.text('ملفات مشاريع تالفة لا يمكن فتحها: 1'), findsOneWidget);
  });

  testWidgets('new project → import → delete → undo → redo → back', (t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();

    await t.tap(find.text('مشروع جديد'));
    await t.pumpAndSettle();
    expect(find.text('أضف مقاطع فيديو من المعرض للبدء'), findsOneWidget);

    await t.tap(find.text('إضافة فيديو'));
    await t.pumpAndSettle();
    expect(find.text('مقطعان'), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('total-duration'))).data,
      '1:09',
    );

    await t.tap(find.byTooltip('حذف المقطع').first);
    await t.pumpAndSettle();
    expect(find.text('مقطع واحد'), findsOneWidget);

    await t.tap(find.byTooltip('تراجع'));
    await t.pumpAndSettle();
    expect(find.text('مقطعان'), findsOneWidget);

    await t.tap(find.byTooltip('إعادة'));
    await t.pumpAndSettle();
    expect(find.text('مقطع واحد'), findsOneWidget);

    await t.tap(find.byTooltip('تراجع'));
    await t.pumpAndSettle();

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(
      find.text('مقطعان · 1:09'),
      findsOneWidget,
      reason: 'saved and listed',
    );
  });

  testWidgets('failed imports are shown to the user', (t) async {
    picker.paths = ['/cache/a.mp4', '/cache/broken.mp4'];
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('مشروع جديد'));
    await t.pumpAndSettle();
    await t.tap(find.text('إضافة فيديو'));
    await t.pumpAndSettle();

    expect(find.text('مقطع واحد'), findsOneWidget);
    expect(find.textContaining('broken.mp4'), findsOneWidget);
  });

  testWidgets('a project that cannot be loaded shows a message', (t) async {
    repo = _VanishingRepository();
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('سيختفي'));
    await t.pumpAndSettle();
    expect(find.text('تعذّر فتح المشروع'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing, reason: 'stayed on home');
  });

  testWidgets('autosave failure shows a warning in the editor', (t) async {
    repo = _FailingSaveRepository();
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('مشروع جديد'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('save-error')), findsOneWidget);
  });

  testWidgets('double tap on "new project" creates only one', (t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('مشروع جديد'));
    await t.tap(find.text('مشروع جديد'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(repo.projects, hasLength(1));
  });
}

/// Lists a project, but it is gone by the time it is opened.
class _VanishingRepository extends InMemoryProjectRepository {
  _VanishingRepository() : super([EditProject(id: 'gone', name: 'سيختفي')]);

  @override
  Future<EditProject?> load(String id) async => null;
}

class _FailingSaveRepository extends InMemoryProjectRepository {
  @override
  Future<void> save(EditProject project) async =>
      throw const FormatException('disk full');
}
