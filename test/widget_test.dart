import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/features/editor/editor_controller.dart';
import 'package:laqta/features/home/home_screen.dart';
import 'package:laqta/main.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('app starts in Arabic, right-to-left, with empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(
            InMemoryProjectRepository(),
          ),
        ],
        child: const LaqtaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لقطة'), findsOneWidget);
    expect(find.text('لا توجد مشاريع بعد'), findsOneWidget);

    final context = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
