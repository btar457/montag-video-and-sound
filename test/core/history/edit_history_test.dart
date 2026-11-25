import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/history/edit_history.dart';

void main() {
  test('starts with nothing to undo or redo', () {
    final h = EditHistory('a');
    expect(h.present, 'a');
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
  });

  test('undo and redo walk through snapshots', () {
    var h = EditHistory('a').push('b').push('c');
    h = h.undo();
    expect(h.present, 'b');
    h = h.undo();
    expect(h.present, 'a');
    expect(h.canUndo, isFalse);
    h = h.redo().redo();
    expect(h.present, 'c');
    expect(h.canRedo, isFalse);
  });

  test('pushing after undo discards the redo branch', () {
    final h = EditHistory('a').push('b').undo().push('x');
    expect(h.present, 'x');
    expect(h.canRedo, isFalse);
    expect(h.undo().present, 'a');
  });

  test('undo/redo at the ends returns the same history', () {
    final h = EditHistory('a');
    expect(identical(h.undo(), h), isTrue);
    expect(identical(h.redo(), h), isTrue);
  });

  test('pushing the identical snapshot is a no-op', () {
    final h = EditHistory('a');
    expect(identical(h.push(h.present), h), isTrue);
  });

  test('keeps at most limit undo steps, dropping the oldest', () {
    var h = EditHistory(0, limit: 3);
    for (var i = 1; i <= 5; i++) {
      h = h.push(i);
    }
    expect(h.past, [2, 3, 4]);
    h = h.undo().undo().undo();
    expect(h.present, 2);
    expect(h.canUndo, isFalse);
  });

  test('rejects a limit below 1', () {
    expect(() => EditHistory('a', limit: 0), throwsArgumentError);
  });
}
