import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/main.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('app starts in Arabic, right-to-left, with empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const LaqtaApp());
    await tester.pumpAndSettle();

    expect(find.text('لقطة'), findsOneWidget);
    expect(find.text('لا توجد مشاريع بعد'), findsOneWidget);

    final context = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
