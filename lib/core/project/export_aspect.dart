/// Output frame shape for the exported video.
enum ExportAspect {
  /// 9:16 vertical — TikTok, Reels, Shorts.
  portrait(9, 16),

  /// 16:9 horizontal — YouTube.
  landscape(16, 9),

  /// 1:1 square — Instagram feed.
  square(1, 1);

  const ExportAspect(this.widthUnits, this.heightUnits);

  final int widthUnits;
  final int heightUnits;

  double get ratio => widthUnits / heightUnits;

  /// Output size in pixels whose short side is about [shortSide].
  ///
  /// Both sides are rounded up to even numbers because H.264 encoders
  /// reject odd dimensions, so an odd [shortSide] grows by one
  /// (1079 → 1080).
  (int width, int height) sizeForShortSide(int shortSide) {
    if (shortSide <= 0) {
      throw ArgumentError.value(shortSide, 'shortSide', 'must be positive');
    }
    final short = _even(shortSide);
    if (widthUnits <= heightUnits) {
      return (short, _even(short * heightUnits / widthUnits));
    }
    return (_even(short * widthUnits / heightUnits), short);
  }

  static int _even(num value) {
    final rounded = value.round();
    return rounded.isEven ? rounded : rounded + 1;
  }
}
