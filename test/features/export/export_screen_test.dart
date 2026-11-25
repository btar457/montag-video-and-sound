import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/export/export_request.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/core/project/export_aspect.dart';
import 'package:laqta/features/editor/editor_controller.dart';
import 'package:laqta/features/export/export_engine.dart';
import 'package:laqta/features/export/export_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fakes.dart';

class _FakeEngine implements ExportEngine {
  final requests = <ExportRequest>[];
  StreamController<ExportEvent>? events;
  int cancels = 0;

  @override
  Stream<ExportEvent> start(ExportRequest request) {
    requests.add(request);
    events = StreamController<ExportEvent>();
    return events!.stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    events?.add(const ExportCancelled());
  }
}

void main() {
  late _FakeEngine engine;
  late ProviderContainer container;

  Future<void> pump(WidgetTester t, {bool withClips = true}) async {
    engine = _FakeEngine();
    container = ProviderContainer.test(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          InMemoryProjectRepository(),
        ),
        exportEngineProvider.overrideWithValue(engine),
        exportDirectoryProvider.overrideWithValue(Directory('/cache/exports')),
      ],
    );
    var project = EditProject(id: 'p', name: 'x');
    if (withClips) {
      project = project.addClip(
        Clip.full(
          id: 'a',
          sourcePath: '/media/a.mp4',
          sourceDuration: const Duration(seconds: 12),
        ),
      );
    }
    container.read(editorControllerProvider.notifier).open(project);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ExportScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('shows summary and changes aspect and quality', (t) async {
    await pump(t);
    expect(find.text('مقطع واحد · 0:12 · 1080×1920'), findsOneWidget);

    await t.tap(find.text('16:9'));
    await t.pumpAndSettle();
    expect(
      container.read(editorControllerProvider)!.project.aspect,
      ExportAspect.landscape,
    );
    await t.tap(find.text('720p'));
    await t.pumpAndSettle();
    expect(find.text('مقطع واحد · 0:12 · 1280×720'), findsOneWidget);
  });

  testWidgets('start sends the request into the export dir; progress; done', (
    t,
  ) async {
    await pump(t);
    await t.tap(find.text('ابدأ التصدير'));
    await t.pump();

    final r = engine.requests.single;
    expect(r.outputPath, startsWith('/cache/exports/'));
    expect(r.outputPath, endsWith('.mp4'));
    expect((r.width, r.height), (1080, 1920));
    expect(find.text('جارٍ التحضير…'), findsOneWidget);

    engine.events!.add(const ExportProgress(0.42));
    await t.pump();
    expect(find.text('جارٍ التصدير 42٪'), findsOneWidget);
    expect(
      t
          .widget<SegmentedButton<ExportQuality>>(
            find.byType(SegmentedButton<ExportQuality>),
          )
          .onSelectionChanged,
      isNull,
      reason: 'settings locked while rendering',
    );

    engine.events!.add(ExportDone(r.outputPath));
    await t.pump();
    expect(find.text('اكتمل التصدير'), findsOneWidget);

    // Settings unlock again, and another export can be started.
    await t.tap(find.text('720p'));
    await t.pump();
    await t.tap(find.text('تصدير مرة أخرى'));
    await t.pump();
    expect(engine.requests, hasLength(2));
    expect(
      (engine.requests.last.width, engine.requests.last.height),
      (720, 1280),
    );
  });

  testWidgets('failure offers a retry', (t) async {
    await pump(t);
    await t.tap(find.text('ابدأ التصدير'));
    await t.pump();
    engine.events!.add(const ExportFailed('transformer_7001'));
    await t.pump();
    expect(find.text('تعذّر تصدير الفيديو'), findsOneWidget);
    expect(find.textContaining('7001'), findsNothing, reason: 'no raw codes');

    await t.tap(find.text('حاول مرة أخرى'));
    await t.pump();
    expect(engine.requests, hasLength(2));
  });

  testWidgets('busy gets its own message', (t) async {
    await pump(t);
    await t.tap(find.text('ابدأ التصدير'));
    await t.pump();
    engine.events!.add(const ExportFailed('busy'));
    await t.pump();
    expect(find.textContaining('تصدير آخر قيد التنفيذ'), findsOneWidget);
  });

  testWidgets('cancel returns to setup', (t) async {
    await pump(t);
    await t.tap(find.text('ابدأ التصدير'));
    await t.pump();
    await t.tap(find.text('إلغاء'));
    await t.pump();
    expect(engine.cancels, 1);
    expect(find.text('ابدأ التصدير'), findsOneWidget);
  });

  testWidgets('leaving during an export cancels it', (t) async {
    await pump(t);
    await t.tap(find.text('ابدأ التصدير'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    expect(engine.cancels, 1);
  });

  testWidgets('an empty project cannot be exported', (t) async {
    await pump(t, withClips: false);
    expect(find.text('أضف مقاطع قبل التصدير'), findsOneWidget);
    expect(find.text('ابدأ التصدير'), findsNothing);
  });
}
