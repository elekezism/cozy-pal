import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hand-drawn look: maroon-brown ink, warm pastels, wobbly outlines.
const ink = Color(0xFF5B2B2A);

class Pal {
  static const sky = Color(0xFFBDE8F1);
  static const wallL = Color(0xFFFBE6BF);
  static const wallR = Color(0xFFF7EBD6);
  static const wallTop = Color(0xFFE9CFAE);
  static const wallCap = Color(0xFFD9B48E);
  static const floor = Color(0xFFDDAA78);
  static const plank = Color(0xFFBF8A5A);
  static const slabL = Color(0xFFB8794C);
  static const slabR = Color(0xFFA9693F);
  static const wood = Color(0xFFC98B5A);
  static const woodDark = Color(0xFFA86E45);
  static const woodLight = Color(0xFFE2AE7C);
  static const cream = Color(0xFFFFF8E8);
  static const note = Color(0xFFFFF3B0);
  static const sage = Color(0xFFB5D37F);
  static const sageDark = Color(0xFF8DB45E);
  static const tomato = Color(0xFFE2725B);
  static const mustard = Color(0xFFF2C14E);
  static const blue = Color(0xFF8FC0DE);
  static const lilac = Color(0xFFC9A7E0);
  static const pink = Color(0xFFF4B6B0);
  static const mint = Color(0xFFA8DCC9);
}

/// The bundled hand-lettered font (assets/fonts/PatrickHand-Regular.ttf).
const handFont = 'PatrickHand';

Paint fillPaint(Color c) => Paint()..color = c;

Paint inkPaint(double width, [Color c = ink]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Lighten (amt > 0) or darken (amt < 0) a color.
Color shade(Color c, double amt) {
  int f(double v) {
    final x = v * 255;
    return (amt < 0 ? x * (1 + amt) : x + (255 - x) * amt).round().clamp(0, 255);
  }

  return Color.fromARGB((c.a * 255).round(), f(c.r), f(c.g), f(c.b));
}

/// Small seeded random so wobbles stay put from frame to frame.
class SeededRandom {
  SeededRandom(num seed) : _s = ((seed * 1000).round() & 0xFFFFFFFF) == 0 ? 1 : (seed * 1000).round() & 0xFFFFFFFF;
  int _s;
  double next() {
    _s = (_s * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _s / 4294967296.0;
  }
}

/// A closed outline through [pts] whose edges wobble slightly, like ink.
Path wobblePath(List<Offset> pts, num seed, double unit, [double amp = 0.55]) {
  final r = SeededRandom(seed * 9301 + 49297);
  final a = amp * unit * 0.09;
  final path = Path();
  for (var i = 0; i < pts.length; i++) {
    final p0 = pts[i], p1 = pts[(i + 1) % pts.length];
    final d = p1 - p0;
    final len = d.distance;
    final n = math.max(1, (len / (unit * 0.9)).round());
    final normal = len == 0 ? Offset.zero : Offset(-d.dy / len, d.dx / len);
    if (i == 0) path.moveTo(p0.dx, p0.dy);
    for (var k = 1; k <= n; k++) {
      final t = k / n;
      final j = k == n ? 0.0 : (r.next() - 0.5) * 2 * a;
      final q = p0 + d * t + normal * j;
      path.lineTo(q.dx, q.dy);
    }
  }
  return path..close();
}

/// A rounded rectangle drawn by hand: filled, inked, with an optional
/// offset "shadow" underneath for a chunky sticker feel.
class DoodleBox extends StatelessWidget {
  const DoodleBox({
    super.key,
    required this.child,
    this.color = Pal.cream,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.radius = 16,
    this.shadow = 0,
    this.border = true,
    this.seed = 1,
    this.tilt = 0,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double shadow;
  final bool border;
  final int seed;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: CustomPaint(
        painter: _DoodleBoxPainter(color, radius, shadow, border, seed),
        child: Padding(
          padding: EdgeInsets.only(bottom: shadow),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _DoodleBoxPainter extends CustomPainter {
  _DoodleBoxPainter(this.color, this.radius, this.shadow, this.border, this.seed);
  final Color color;
  final double radius;
  final double shadow;
  final bool border;
  final int seed;

  Path _shape(Rect r) {
    // sample a rounded rect and wobble it
    final rr = math.min(radius, math.min(r.width, r.height) / 2);
    final pts = <Offset>[];
    void arc(Offset c, double start) {
      for (var i = 0; i <= 4; i++) {
        final a = start + i * math.pi / 8;
        pts.add(c + Offset(math.cos(a), math.sin(a)) * rr);
      }
    }

    arc(Offset(r.right - rr, r.top + rr), -math.pi / 2);
    arc(Offset(r.right - rr, r.bottom - rr), 0);
    arc(Offset(r.left + rr, r.bottom - rr), math.pi / 2);
    arc(Offset(r.left + rr, r.top + rr), math.pi);
    return wobblePath(pts, seed, 18, 0.9);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3 - shadow);
    if (shadow > 0) canvas.drawPath(_shape(body.shift(Offset(0, shadow))), fillPaint(ink));
    final p = _shape(body);
    canvas.drawPath(p, fillPaint(color));
    if (border) canvas.drawPath(p, inkPaint(2.4));
  }

  @override
  bool shouldRepaint(_DoodleBoxPainter old) =>
      old.color != color || old.radius != radius || old.shadow != shadow || old.border != border;
}

/// Round chunky button, like a sticker.
class DoodleButton extends StatelessWidget {
  const DoodleButton({
    super.key,
    required this.onTap,
    required this.child,
    this.color = Pal.cream,
    this.size = 48,
    this.tooltip,
  });

  final VoidCallback? onTap;
  final Widget child;
  final Color color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: ink, width: 2.5),
          boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 3))],
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: Semantics(button: true, label: tooltip, child: btn));
  }
}
