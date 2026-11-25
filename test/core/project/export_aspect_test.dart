import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/project/export_aspect.dart';

void main() {
  test('1080p sizes for each aspect', () {
    expect(ExportAspect.portrait.sizeForShortSide(1080), (1080, 1920));
    expect(ExportAspect.landscape.sizeForShortSide(1080), (1920, 1080));
    expect(ExportAspect.square.sizeForShortSide(1080), (1080, 1080));
  });

  test('dimensions are always even', () {
    for (final aspect in ExportAspect.values) {
      for (final side in [361, 481, 719, 1079]) {
        final (w, h) = aspect.sizeForShortSide(side);
        expect(w.isEven && h.isEven, isTrue, reason: '$aspect @ $side');
      }
    }
  });

  test('odd short side is rounded up to the next even number', () {
    expect(ExportAspect.portrait.sizeForShortSide(1079), (1080, 1920));
  });

  test('rejects non-positive sizes', () {
    expect(() => ExportAspect.square.sizeForShortSide(0), throwsArgumentError);
    expect(
      () => ExportAspect.square.sizeForShortSide(-720),
      throwsArgumentError,
    );
  });
}
