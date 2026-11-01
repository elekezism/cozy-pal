import 'dart:math' as math;
import 'dart:ui';

/// A box in room ("world") units. The floor is 10 x 10, walls are 7 high.
/// +x runs toward the bottom-right of the screen, +y toward the bottom-left.
class WorldBox {
  const WorldBox(this.x0, this.y0, this.x1, this.y1, this.z1);
  final double x0, y0, x1, y1, z1;
  double get depth => (x0 + x1) / 2 + (y0 + y1) / 2;
}

/// Isometric projection fitted to the room area of the screen.
class RoomLayout {
  RoomLayout(this.size)
      // the room is 18 units wide on screen (walls included): keep it inside
      // the width with a small margin, so narrow phones don't cut the walls off
      : t = math.min(size.width * 0.96 / 18.0, size.height / 17.2) {
    ox = size.width / 2;
    oy = (size.height - 17.9 * t) / 2 + 7.6 * t;
  }

  final Size size;

  /// One world unit in pixels.
  final double t;
  late final double ox, oy;

  static const n = 10.0, wallH = 7.0, wallT = 0.4, slab = 0.6;

  Offset iso(double x, double y, [double z = 0]) =>
      Offset(ox + (x - y) * t * 0.8660, oy + (x + y) * t * 0.5 - z * t);

  Offset at(Offset world) => iso(world.dx, world.dy);

  // Furniture
  static const shelf = WorldBox(0, 4.4, 1.3, 7.6, 5.2);
  static const wardrobe = WorldBox(0.9, 0, 3.5, 1.2, 5.3);
  static const desk = WorldBox(4.3, 0, 7.6, 1.6, 3.8);
  static const mailbox = WorldBox(6.0, 8.8, 7.1, 9.8, 3.6);
  static const crate = WorldBox(2.4, 7.7, 4.0, 9.1, 1.3);

  /// Pet height in pixels.
  double get petHeight => 3.1 * t;

  /// Screen rectangle around a box, for taps.
  Rect screenRect(WorldBox b, [double pad = 0.2]) {
    var l = double.infinity, tp = double.infinity, r = -double.infinity, bt = -double.infinity;
    for (final x in [b.x0, b.x1]) {
      for (final y in [b.y0, b.y1]) {
        for (final z in [0.0, b.z1]) {
          final p = iso(x, y, z);
          l = math.min(l, p.dx);
          r = math.max(r, p.dx);
          tp = math.min(tp, p.dy);
          bt = math.max(bt, p.dy);
        }
      }
    }
    return Rect.fromLTRB(l - pad * t, tp - pad * t, r + pad * t, bt + pad * t);
  }
}
