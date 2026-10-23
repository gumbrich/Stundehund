import 'dart:ui';

const compactBarHeight = 202.0;

/// Keep the user's screen and top-left anchor when changing app layouts.
/// Native minimise/restore is deliberately left to the operating system.
class WindowGeometry {
  Size _expandedSize = const Size(1120, 820);

  Rect forMode(Rect current, {required bool compact}) {
    if (compact) _expandedSize = current.size;
    final size = compact
        ? Size(current.width, compactBarHeight)
        : _expandedSize;
    return Rect.fromLTWH(current.left, current.top, size.width, size.height);
  }
}
