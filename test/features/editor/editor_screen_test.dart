import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/features/editor/clip_preview.dart';
import 'package:laqta/features/editor/editor_controller.dart';
import 'package:laqta/features/editor/editor_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fakes.dart';

/// Stand-in for the video player: a button that "seeks" to 3s of source.
Widget _fakePreview(Clip clip, ValueNotifier<Duration> position) => TextButton(
  key: const Key('fake-seek'),
  onPressed: () => position.value = const Duration(seconds: 3),
  child: Text('preview ${clip.id}'),
);

void main() {
  late ProviderContainer container;

  EditorState state() => container.read(editorControllerProvider)!;

  Future<void> pumpEditor(WidgetTester t) async {
    container = ProviderContainer.test(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          InMemoryProjectRepository(),
        ),
        clipPreviewProvider.overrideWithValue(_fakePreview),
      ],
    );
    container
        .read(editorControllerProvider.notifier)
        .open(
          EditProject(id: 'p', name: 'تجربة')
              .addClip(
                Clip.full(
                  id: 'a',
                  sourcePath: '/m/a.mp4',
                  sourceDuration: const Duration(seconds: 10),
                ),
              )
              .addClip(
                Clip.full(
                  id: 'b',
                  sourcePath: '/m/b.mp4',
                  sourceDuration: const Duration(seconds: 5),
                ),
              ),
        );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const EditorScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('tapping a clip opens its panel; tapping again closes it', (
    t,
  ) async {
    await pumpEditor(t);
    expect(find.byType(RangeSlider), findsNothing);

    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();
    expect(find.text('preview a'), findsOneWidget);
    expect(find.text('من 0:00 إلى 0:10'), findsOneWidget);

    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();
    expect(find.byType(RangeSlider), findsNothing);
  });

  testWidgets('finishing a slider drag trims the clip (clamped)', (t) async {
    await pumpEditor(t);
    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();

    final slider = t.widget<RangeSlider>(find.byType(RangeSlider));
    slider.onChangeEnd!(const RangeValues(2000, 2030)); // too short
    await t.pumpAndSettle();

    final clip = state().project.clips.first;
    expect(clip.trimStart, const Duration(seconds: 2));
    expect(clip.trimEnd, const Duration(milliseconds: 2100));
    expect(find.byKey(const Key('total-duration')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('total-duration'))).data,
      '0:05',
      reason: '0.1s + 5s',
    );
  });

  testWidgets('split is disabled at the start and works at the playhead', (
    t,
  ) async {
    await pumpEditor(t);
    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();

    FilledButton split() => t.widget<FilledButton>(
      find.ancestor(
        of: find.text('تقسيم هنا'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(split().onPressed, isNull, reason: 'playhead at clip start');

    await t.tap(find.byKey(const Key('fake-seek'))); // playhead → 3s
    await t.pumpAndSettle();
    expect(split().onPressed, isNotNull);

    await t.tap(find.text('تقسيم هنا'));
    await t.pumpAndSettle();
    final clips = state().project.clips;
    expect(clips, hasLength(3));
    expect(clips[0].duration, const Duration(seconds: 3));
    expect(clips[1].duration, const Duration(seconds: 7));
    expect(find.text('من 0:00 إلى 0:03'), findsOneWidget);
  });

  testWidgets('deleting the selected clip closes the panel', (t) async {
    await pumpEditor(t);
    await t.tap(find.text('مقطع 2'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('حذف المقطع').last);
    await t.pumpAndSettle();
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.text('preview b'), findsNothing);
  });

  FilledButton splitButton(WidgetTester t) => t.widget<FilledButton>(
    find.ancestor(
      of: find.text('تقسيم هنا'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  testWidgets('undo that removes the selected clip closes the panel', (
    t,
  ) async {
    await pumpEditor(t);
    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('fake-seek')));
    await t.pumpAndSettle();
    await t.tap(find.text('تقسيم هنا'));
    await t.pumpAndSettle();

    await t.tap(find.text('مقطع 2')); // the new second half
    await t.pumpAndSettle();
    expect(find.text('من 0:03 إلى 0:10'), findsOneWidget);

    await t.tap(find.byTooltip('تراجع'));
    await t.pumpAndSettle();
    expect(state().project.clips, hasLength(2));
    expect(find.byType(RangeSlider), findsNothing);
  });

  testWidgets('switching clips resets the playhead (split disabled)', (
    t,
  ) async {
    await pumpEditor(t);
    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('fake-seek')));
    await t.pumpAndSettle();
    expect(splitButton(t).onPressed, isNotNull);

    await t.tap(find.text('مقطع 2'));
    await t.pumpAndSettle();
    expect(find.text('preview b'), findsOneWidget);
    expect(splitButton(t).onPressed, isNull);
  });

  testWidgets('trim slider runs left-to-right even in Arabic', (t) async {
    await pumpEditor(t);
    await t.tap(find.text('مقطع 1'));
    await t.pumpAndSettle();
    final ctx = t.element(find.byType(RangeSlider));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(
      Directionality.of(t.element(find.text('تقسيم هنا'))),
      TextDirection.rtl,
    );
  });

  for (final size in [const Size(640, 360), const Size(360, 640)]) {
    testWidgets('panel fits without overflow at ${size.width}x${size.height}', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpEditor(t);
      await t.tap(find.text('مقطع 1'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('مقطع 2'), findsOneWidget, reason: 'list still visible');
    });
  }
}
