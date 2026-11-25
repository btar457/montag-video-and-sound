import 'dart:math';

/// Matches ids that are safe to use as file names: no separators, no dots,
/// so a crafted id can never escape the projects directory.
final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

bool isSafeId(String id) => _safeId.hasMatch(id);

/// Generates unique, file-name-safe ids such as `mf3k2x9c-4h7q2z1p`.
///
/// Time prefix keeps ids roughly sortable; the random suffix makes
/// collisions practically impossible even within the same microsecond.
class IdGenerator {
  IdGenerator({Random? random, DateTime Function()? clock})
    : _random = random ?? Random.secure(),
      _clock = clock ?? DateTime.now;

  static const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  final Random _random;
  final DateTime Function() _clock;

  String next() {
    final time = _clock().microsecondsSinceEpoch.toRadixString(36);
    final suffix = String.fromCharCodes(
      List.generate(
        8,
        (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
      ),
    );
    return '$time-$suffix';
  }
}
