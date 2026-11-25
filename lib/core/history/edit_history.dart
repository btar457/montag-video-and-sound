/// Undo/redo history over immutable snapshots.
///
/// Immutable: every operation returns a new history. Keeps at most [limit]
/// undo steps; the oldest are dropped first.
class EditHistory<T> {
  EditHistory(this.present, {this.limit = 100})
    : past = const [],
      future = const [] {
    if (limit < 1) throw ArgumentError.value(limit, 'limit', 'must be >= 1');
  }

  EditHistory._(this.past, this.present, this.future, this.limit);

  final List<T> past;
  final T present;
  final List<T> future;
  final int limit;

  bool get canUndo => past.isNotEmpty;
  bool get canRedo => future.isNotEmpty;

  /// Records [next] as the new present. Clears the redo stack.
  /// Pushing the identical object is a no-op.
  EditHistory<T> push(T next) {
    if (identical(next, present)) return this;
    final newPast = [...past, present];
    if (newPast.length > limit) newPast.removeAt(0);
    return EditHistory._(List.unmodifiable(newPast), next, const [], limit);
  }

  EditHistory<T> undo() {
    if (!canUndo) return this;
    return EditHistory._(
      List.unmodifiable(past.sublist(0, past.length - 1)),
      past.last,
      List.unmodifiable([present, ...future]),
      limit,
    );
  }

  EditHistory<T> redo() {
    if (!canRedo) return this;
    return EditHistory._(
      List.unmodifiable([...past, present]),
      future.first,
      List.unmodifiable(future.sublist(1)),
      limit,
    );
  }
}
