import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'doodle.dart';
import 'pet_painter.dart';
import 'room_layout.dart';

export 'doodle.dart' show ink, inkPaint, fillPaint, Pal, handFont;

/// Fills a path then outlines it in the hand-drawn ink style.
void inked(Canvas c, Path p, Color color, double u, [double weight = 0.55]) {
  c.drawPath(p, fillPaint(color));
  c.drawPath(p, inkPaint(weight * u));
}

/// The cozy room as a hand-drawn isometric diorama floating in the sky:
/// bookshelf (ask), wardrobe (friends), desk with microphone (notes),
/// mailbox (email), notes crate, rug, cushion and treat bowl.
/// The pet is drawn in depth order so it walks in front of / behind things.
class RoomPainter extends CustomPainter {
  RoomPainter({
    required this.time,
    required this.noteCount,
    required this.treats,
    required this.mailFlagUp,
    required this.recording,
    required this.searching,
    required this.pet,
    required this.petWorld,
  });

  final double time;
  final int noteCount;
  final int treats;
  final bool mailFlagUp;
  final bool recording;
  final bool searching;
  final PetPainter pet;
  final Offset petWorld;

  late RoomLayout l;
  double get t => l.t;
  Offset iso(double x, double y, [double z = 0]) => l.iso(x, y, z);

  // ---------------------------------------------------------------- caching
  // Static parts are recorded once into Pictures; only small animated bits
  // (clouds, twinkling lights, the pet) are drawn every frame.
  static final Map<String, ui.Picture> _cache = {};
  static Size? _cacheSize;

  void _cached(Canvas c, String key, void Function(Canvas c) draw) {
    var pic = _cache[key];
    if (pic == null) {
      final rec = ui.PictureRecorder();
      draw(Canvas(rec));
      pic = rec.endRecording();
      _cache[key] = pic;
    }
    c.drawPicture(pic);
  }

  // ---------------------------------------------------------------- drawing helpers
  void shape(Canvas c, List<Offset> pts, Color color, num seed, [double w = 1]) {
    final p = wobblePath(pts, seed, t);
    c.drawPath(p, fillPaint(color));
    c.drawPath(p, inkPaint(math.max(1.2, t * 0.085 * w)));
  }

  void quad(Canvas c, List<double> a, List<double> b, List<double> cc, List<double> d, Color color, num seed,
          [double w = 1]) =>
      shape(c, [iso(a[0], a[1], a[2]), iso(b[0], b[1], b[2]), iso(cc[0], cc[1], cc[2]), iso(d[0], d[1], d[2])],
          color, seed, w);

  void line3(Canvas c, List<double> a, List<double> b, [double w = 0.8, Color col = ink]) {
    c.drawLine(iso(a[0], a[1], a[2]), iso(b[0], b[1], b[2]), inkPaint(math.max(1, t * 0.085 * w), col));
  }

  /// Three visible faces of a box: front-left (+y), front-right (+x), top.
  void box(Canvas c, double x0, double y0, double z0, double x1, double y1, double z1, Color col, num seed,
      {Color? left, Color? right, Color? top}) {
    quad(c, [x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1], left ?? shade(col, -0.08), seed + 1);
    quad(c, [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1], right ?? shade(col, -0.18), seed + 2);
    quad(c, [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], top ?? col, seed + 3);
  }

  void flatCircle(Canvas c, double cx, double cy, double r, double z, Color color, num seed, [double w = 1]) {
    final pts = [
      for (var i = 0; i < 20; i++)
        iso(cx + math.cos(i / 20 * math.pi * 2) * r, cy + math.sin(i / 20 * math.pi * 2) * r, z)
    ];
    shape(c, pts, color, seed, w);
  }

  void stroke(Canvas c, Path p, [double w = 1]) => c.drawPath(p, inkPaint(math.max(1.2, t * 0.085 * w)));

  void sparkle(Canvas c, Offset o, double r, Color col) {
    final p = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx + r * 0.15, o.dy - r * 0.15, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx + r * 0.15, o.dy + r * 0.15, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx - r * 0.15, o.dy + r * 0.15, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx - r * 0.15, o.dy - r * 0.15, o.dx, o.dy - r);
    c.drawPath(p, inkPaint(math.max(1, t * 0.06), col));
  }

  void plant(Canvas c, double x, double y, double z, double k, int seed) {
    final base = iso(x, y, z);
    final s = t * k;
    final r = SeededRandom(seed);
    for (var i = 0; i < 5; i++) {
      final a = -1.1 + i * 0.55 + (r.next() - 0.5) * 0.2;
      final len = s * (2.2 + r.next() * 0.8);
      final tip = Offset(base.dx + math.sin(a) * len, base.dy - s * 1.2 - math.cos(a) * len);
      final leaf = Path()
        ..moveTo(base.dx, base.dy - s * 1.2)
        ..quadraticBezierTo(tip.dx - s * 0.7, (tip.dy + base.dy) / 2 - s * 0.6, tip.dx, tip.dy)
        ..quadraticBezierTo(tip.dx + s * 0.6, (tip.dy + base.dy) / 2, base.dx, base.dy - s * 1.2);
      c.drawPath(leaf, fillPaint(i.isOdd ? Pal.sage : Pal.sageDark));
      stroke(c, leaf, 0.7);
    }
    final pot = wobblePath([
      base + Offset(-s * 0.9, -s * 1.3),
      base + Offset(s * 0.9, -s * 1.3),
      base + Offset(s * 0.65, 0),
      base + Offset(-s * 0.65, 0),
    ], seed + 7, t);
    c.drawPath(pot, fillPaint(Pal.tomato));
    stroke(c, pot, 0.8);
  }

  // ---------------------------------------------------------------- paint
  @override
  void paint(Canvas canvas, Size size) {
    l = RoomLayout(size);
    if (_cacheSize != size) {
      _cache.clear();
      _cacheSize = size;
    }
    final hour = DateTime.now().hour;
    final night = hour < 6 || hour >= 19;
    final dusk = hour == 18 || hour == 6;

    _sky(canvas, size);
    _cached(canvas, 'shell:$night:$dusk', (c) => _shell(c, night, dusk));
    _lights(canvas);
    _cached(canvas, 'rug', _rug);
    _cached(canvas, 'cushion', _cushion);

    final items = <(double, void Function())>[
      (2.8, () => _cached(canvas, 'wardrobe', _wardrobe)),
      (4.5, () => _cached(canvas, 'plant', (c) {
            box(c, 0.25, 3.6, 0, 0.85, 4.2, 0.8, Pal.blue, 141);
            plant(c, 0.55, 3.9, 0.8, 0.6, 142);
          })),
      (6.65, () => _cached(canvas, 'shelf:$searching', (c) => _shelf(c, searching))),
      (6.8, () {
        _cached(canvas, 'desk:$recording', (c) => _desk(c, recording));
        if (recording) {
          final g = 0.5 + 0.5 * math.sin(time * 8);
          canvas.drawCircle(iso(LayoutSpots.micX, LayoutSpots.micY, 3.3), t * (0.9 + 0.25 * g),
              fillPaint(Pal.tomato.withValues(alpha: 0.12 + 0.1 * g)));
        }
      }),
      (11.6, () => _cached(canvas, 'crate:$noteCount', (c) => _crate(c, noteCount))),
      (14.8, () => _cached(canvas, 'bowl:${math.min(treats, 3)}', (c) => _bowl(c, treats))),
      (15.85, () => _mailbox(canvas)),
      (petWorld.dx + petWorld.dy + 0.5, () => pet.paint(canvas, size)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
  }

  void _sky(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, fillPaint(Pal.sky));
    final r = SeededRandom(5);
    final cloud = fillPaint(Colors.white.withValues(alpha: 0.75));
    for (var i = 0; i < 5; i++) {
      final cx = ((r.next() * size.width + time * (6 + i * 2)) % (size.width + 160)) - 80;
      final cy = size.height * (0.08 + r.next() * 0.85);
      final s = t * (1.6 + r.next() * 1.6);
      c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: s * 3.2, height: s * 1.4), cloud);
      c.drawOval(Rect.fromCenter(center: Offset(cx - s, cy + s * 0.15), width: s * 2, height: s * 1.1), cloud);
      c.drawOval(Rect.fromCenter(center: Offset(cx + s * 0.9, cy - s * 0.2), width: s * 2.2, height: s * 1.5), cloud);
    }
  }

  void _shell(Canvas c, bool night, bool dusk) {
    const n = RoomLayout.n, h = RoomLayout.wallH, wt = RoomLayout.wallT, sl = RoomLayout.slab;
    quad(c, [0, n, 0], [n, n, 0], [n, n, -sl], [0, n, -sl], Pal.slabL, 11);
    quad(c, [n, 0, 0], [n, n, 0], [n, n, -sl], [n, 0, -sl], Pal.slabR, 12);
    quad(c, [0, 0, 0], [0, n, 0], [0, n, h], [0, 0, h], Pal.wallL, 13);
    quad(c, [0, 0, 0], [n, 0, 0], [n, 0, h], [0, 0, h], Pal.wallR, 14);
    quad(c, [0, n, -sl], [0, n, h], [-wt, n, h], [-wt, n, -sl], Pal.wallCap, 15);
    quad(c, [n, 0, -sl], [n, 0, h], [n, -wt, h], [n, -wt, -sl], Pal.wallCap, 16);
    shape(c, [iso(0, n, h), iso(0, 0, h), iso(n, 0, h), iso(n, -wt, h), iso(-wt, -wt, h), iso(-wt, n, h)],
        Pal.wallTop, 17);
    quad(c, [0, 0, 0], [n, 0, 0], [n, n, 0], [0, n, 0], Pal.floor, 18);
    final r = SeededRandom(77);
    for (var y = 1.0; y < n; y++) {
      line3(c, [0.05, y, 0], [n - 0.05, y, 0], 0.5, Pal.plank);
    }
    for (var y = 0.0; y < n; y++) {
      var x = r.next() * 2.5 + 0.6;
      while (x < n - 0.4) {
        line3(c, [x, y + 0.05, 0], [x, y + 0.95, 0], 0.5, Pal.plank);
        x += 2.6 + r.next() * 1.8;
      }
    }
    line3(c, [0.02, 0.02, 0.35], [0.02, n, 0.35], 0.6, shade(Pal.wallL, -0.25));
    line3(c, [0.02, 0.02, 0.35], [n, 0.02, 0.35], 0.6, shade(Pal.wallR, -0.25));
    const sparkles = [
      [0.0, 0.5, 6.0, 0.28], [0.0, 4.0, 6.1, 0.22], [0.0, 9.0, 5.0, 0.25], [0.0, 8.4, 2.6, 0.2],
      [4.0, 0.0, 6.2, 0.22], [3.9, 0.0, 3.0, 0.24], [7.4, 0.0, 5.8, 0.25], [9.4, 0.0, 6.0, 0.2], [9.5, 0.0, 2.8, 0.2],
    ];
    for (final s in sparkles) {
      sparkle(c, iso(s[0], s[1], s[2]), s[3] * t, shade(Pal.wallL, -0.3));
    }
    _window(c, night, dusk);
    _wallDecor(c);
  }

  void _lights(Canvas c) {
    const z0 = RoomLayout.wallH - 0.55;
    void wire(Offset a, Offset b, double seed) {
      final path = Path();
      for (var i = 0; i <= 24; i++) {
        final k = i / 24, sag = math.sin(k * math.pi) * 0.7;
        final p = iso(a.dx + (b.dx - a.dx) * k, a.dy + (b.dy - a.dy) * k, z0 - sag);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path, inkPaint(math.max(1, t * 0.05)));
      for (var i = 1; i < 9; i++) {
        final k = i / 9, sag = math.sin(k * math.pi) * 0.7;
        final p = iso(a.dx + (b.dx - a.dx) * k, a.dy + (b.dy - a.dy) * k, z0 - sag - 0.25);
        final g = 0.55 + 0.45 * math.sin(time * 2.2 + i * 1.7 + seed);
        c.drawCircle(p, t * 0.42, fillPaint(const Color(0xFFFFE28C).withValues(alpha: 0.28 * g)));
        final bulb = Rect.fromCenter(center: p, width: t * 0.26, height: t * 0.38);
        c.drawOval(bulb, fillPaint(g > 0.7 ? const Color(0xFFFFD66B) : const Color(0xFFFFEFC4)));
        c.drawOval(bulb, inkPaint(math.max(1.2, t * 0.085 * 0.55)));
      }
    }

    wire(const Offset(0.05, 0.3), const Offset(0.05, RoomLayout.n - 0.3), 0);
    wire(const Offset(0.3, 0.05), const Offset(RoomLayout.n - 0.3, 0.05), 3);
  }

  void _window(Canvas c, bool night, bool dusk) {
    const y0 = 1.0, y1 = 3.4, z0 = 2.7, z1 = 5.5;
    final sky = night ? const Color(0xFF3B4A7A) : dusk ? const Color(0xFFF8C29A) : const Color(0xFFCDEEF8);
    quad(c, [0, y0 - 0.2, z0 - 0.2], [0, y1 + 0.2, z0 - 0.2], [0, y1 + 0.2, z1 + 0.2], [0, y0 - 0.2, z1 + 0.2],
        Pal.cream, 21);
    quad(c, [0, y0, z0], [0, y1, z0], [0, y1, z1], [0, y0, z1], sky, 22, 0.8);
    if (night) {
      c.drawCircle(iso(0, y1 - 0.7, z1 - 0.7), t * 0.35, fillPaint(const Color(0xFFFFF3C4)));
    } else {
      for (final p in [
        [y0 + 0.4, z0 + 0.5], [y0 + 1.2, z0 + 0.3], [y1 - 0.6, z0 + 0.6]
      ]) {
        c.drawCircle(iso(0, p[0], p[1]), t * 0.45, fillPaint(Pal.sageDark));
      }
    }
    line3(c, [0, (y0 + y1) / 2, z0], [0, (y0 + y1) / 2, z1], 0.9);
    line3(c, [0, y0, (z0 + z1) / 2], [0, y1, (z0 + z1) / 2], 0.9);
    // gingham café curtain
    const cz = z0 + 1.25;
    quad(c, [0.02, y0 - 0.1, z0], [0.02, y1 + 0.1, z0], [0.02, y1 + 0.1, cz], [0.02, y0 - 0.1, cz],
        const Color(0xFFF7F2F6), 23, 0.8);
    final check = Pal.lilac.withValues(alpha: 0.55);
    for (var k = 0; k < 7; k++) {
      final yy = y0 + k * (y1 - y0) / 6;
      line3(c, [0.03, yy, z0 + 0.05], [0.03, yy, cz - 0.05], 0.9, check);
    }
    for (var k = 1; k < 4; k++) {
      final zz = z0 + k * 0.31;
      line3(c, [0.03, y0, zz], [0.03, y1, zz], 0.9, check);
    }
    box(c, 0, y0 - 0.3, z0 - 0.35, 0.45, y1 + 0.3, z0 - 0.15, Pal.woodLight, 24);
    plant(c, 0.25, (y0 + y1) / 2, z0 - 0.15, 0.55, 25);
  }

  void _wallDecor(Canvas c) {
    // framed paw doodle above the desk
    quad(c, [4.9, 0, 4.0], [6.5, 0, 4.0], [6.5, 0, 5.5], [4.9, 0, 5.5], Pal.lilac, 31);
    quad(c, [5.1, 0.01, 4.2], [6.3, 0.01, 4.2], [6.3, 0.01, 5.3], [5.1, 0.01, 5.3], Pal.cream, 32, 0.6);
    final p = iso(5.7, 0, 4.75), s = t * 0.22;
    final inkFill = fillPaint(ink);
    c.drawOval(Rect.fromCenter(center: p + Offset(0, s), width: s * 2.6, height: s * 2), inkFill);
    for (final d in const [Offset(-1.5, -1), Offset(-0.5, -1.9), Offset(0.6, -1.9), Offset(1.5, -1)]) {
      c.drawCircle(p + d * s, s * 0.55, inkFill);
    }
    // small calendar
    quad(c, [8.3, 0, 3.4], [9.3, 0, 3.4], [9.3, 0, 4.6], [8.3, 0, 4.6], Pal.cream, 33, 0.8);
    quad(c, [8.3, 0.01, 4.3], [9.3, 0.01, 4.3], [9.3, 0.01, 4.6], [8.3, 0.01, 4.6], Pal.tomato, 34, 0.6);
    final dot = fillPaint(ink.withValues(alpha: 0.45));
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        c.drawRect(Rect.fromCenter(center: iso(8.5 + i * 0.3, 0.01, 3.65 + j * 0.22), width: 3, height: 3), dot);
      }
    }
  }

  void _rug(Canvas c) {
    const x0 = 3.0, x1 = 7.2, y0 = 3.2, y1 = 7.4;
    quad(c, [x0, y0, 0.02], [x1, y0, 0.02], [x1, y1, 0.02], [x0, y1, 0.02], const Color(0xFFCFE8F1), 41);
    const sx = (x1 - x0 - 0.6) / 6, sy = (y1 - y0 - 0.6) / 6;
    final pink = fillPaint(Pal.pink.withValues(alpha: 0.55));
    for (var i = 0; i < 6; i++) {
      for (var j = 0; j < 6; j++) {
        if ((i + j).isOdd) continue;
        final a = x0 + 0.3 + i * sx, b = y0 + 0.3 + j * sy;
        c.drawPath(
            Path()
              ..addPolygon([iso(a, b, 0.03), iso(a + sx, b, 0.03), iso(a + sx, b + sy, 0.03), iso(a, b + sy, 0.03)],
                  true),
            pink);
      }
    }
    stroke(
        c,
        wobblePath([
          iso(x0 + 0.3, y0 + 0.3, 0.03),
          iso(x1 - 0.3, y0 + 0.3, 0.03),
          iso(x1 - 0.3, y1 - 0.3, 0.03),
          iso(x0 + 0.3, y1 - 0.3, 0.03)
        ], 42, t),
        0.5);
  }

  void _cushion(Canvas c) {
    const x = 2.4, y = 2.6;
    flatCircle(c, x, y, 1.15, 0.02, shade(Pal.pink, -0.12), 51);
    flatCircle(c, x, y, 1.15, 0.35, Pal.pink, 52);
    flatCircle(c, x, y, 0.78, 0.36, shade(Pal.pink, 0.35), 53, 0.6);
    final p = iso(x + 1.1, y + 1.1, 0.3);
    c.drawCircle(p, t * 0.32, fillPaint(Pal.blue));
    c.drawCircle(p, t * 0.32, inkPaint(math.max(1.2, t * 0.06)));
    c.drawArc(Rect.fromCircle(center: p, radius: t * 0.18), 0.3, 2.3, false, inkPaint(math.max(1, t * 0.035)));
  }

  void _shelf(Canvas c, bool searching) {
    const o = RoomLayout.shelf;
    box(c, o.x0, o.y0, 0, o.x1, o.y1, o.z1, Pal.wood, 61);
    final yA = o.y0 + 0.25, yB = o.y1 - 0.25, x = o.x1 + 0.001;
    quad(c, [x, yA, 0.35], [x, yB, 0.35], [x, yB, o.z1 - 0.3], [x, yA, o.z1 - 0.3], Pal.woodDark, 62, 0.8);
    const cols = [Pal.tomato, Pal.blue, Pal.mustard, Pal.sage, Pal.lilac, Pal.pink, Pal.mint, Pal.cream];
    final r = SeededRandom(7);
    const rows = 4;
    final rowH = (o.z1 - 0.65) / rows;
    for (var s = 0; s < rows; s++) {
      final zb = 0.35 + s * rowH;
      var y = yB - 0.05;
      while (y > yA + 0.25) {
        final bw = 0.22 + r.next() * 0.2, bh = rowH * (0.6 + r.next() * 0.3), roll = r.next();
        final col = cols[(r.next() * cols.length).floor()];
        if (roll < 0.1) {
          if (roll < 0.06) plant(c, x, y - 0.35, zb, 0.32, 63 + s);
          y -= 0.75;
          continue;
        }
        final gone = searching && s == 2 && y < yB - 0.9 && y > yB - 2.0;
        if (!gone) {
          quad(c, [x, y - bw, zb], [x, y, zb], [x, y, zb + bh], [x, y - bw, zb + bh], col, 70 + s * 31 + y * 10, 0.6);
        }
        y -= bw + 0.02;
      }
      quad(c, [x, yA, zb - 0.12], [x, yB, zb - 0.12], [x, yB, zb], [x, yA, zb], Pal.woodLight, 80 + s, 0.6);
    }
  }

  void _wardrobe(Canvas c) {
    const o = RoomLayout.wardrobe;
    for (final xx in [o.x0 + 0.25, o.x1 - 0.25]) {
      box(c, xx - 0.12, o.y1 - 0.3, 0, xx + 0.12, o.y1 - 0.06, 0.15, Pal.woodDark, 92 + xx);
    }
    box(c, o.x0, o.y0, 0.15, o.x1, o.y1, o.z1, Pal.mint, 91, left: shade(Pal.mint, -0.03));
    final xm = (o.x0 + o.x1) / 2;
    line3(c, [xm, o.y1, 0.4], [xm, o.y1, o.z1 - 0.3], 0.8);
    for (final d in [-0.25, 0.25]) {
      final r = Rect.fromCenter(center: iso(xm + d, o.y1, 2.9), width: t * 0.14, height: t * 0.56);
      c.drawOval(r, fillPaint(Pal.cream));
      c.drawOval(r, inkPaint(math.max(1.2, t * 0.05)));
    }
    // a scarf peeking out of the door
    final p = iso(xm, o.y1, 1.6);
    final scarf = Path()
      ..moveTo(p.dx, p.dy)
      ..quadraticBezierTo(p.dx + t * 0.4, p.dy + t * 0.6, p.dx + t * 0.1, p.dy + t * 1.1)
      ..lineTo(p.dx - t * 0.25, p.dy + t * 1.0)
      ..quadraticBezierTo(p.dx, p.dy + t * 0.5, p.dx - t * 0.05, p.dy + t * 0.1)
      ..close();
    c.drawPath(scarf, fillPaint(Pal.tomato));
    stroke(c, scarf, 0.6);
  }

  void _desk(Canvas c, bool rec) {
    const o = RoomLayout.desk;
    const top = 2.2;
    box(c, o.x0, o.y0, 0, o.x0 + 1.4, o.y1 - 0.1, top - 0.25, Pal.cream, 111);
    for (final z in [0.7, 1.35]) {
      line3(c, [o.x0, o.y1 - 0.1, z], [o.x0 + 1.4, o.y1 - 0.1, z], 0.6);
    }
    for (final z in [0.4, 1.05, 1.7]) {
      final q = iso(o.x0 + 0.7, o.y1 - 0.1, z);
      final r = Rect.fromCenter(center: q, width: t * 0.28, height: t * 0.16);
      c.drawOval(r, fillPaint(Pal.mustard));
      c.drawOval(r, inkPaint(math.max(1.2, t * 0.04)));
    }
    for (final xy in [
      [o.x1 - 0.4, o.y0 + 0.15],
      [o.x1 - 0.4, o.y1 - 0.45]
    ]) {
      box(c, xy[0], xy[1], 0, xy[0] + 0.25, xy[1] + 0.25, top - 0.25, Pal.woodDark, 112 + xy[0] * 7 + xy[1]);
    }
    box(c, o.x0, o.y0, top - 0.25, o.x1, o.y1, top, Pal.woodLight, 116);
    box(c, o.x0 + 2.3, o.y0 + 0.15, top, o.x0 + 2.55, o.y0 + 0.8, top + 0.9, Pal.blue, 117);
    box(c, o.x0 + 2.57, o.y0 + 0.15, top, o.x0 + 2.8, o.y0 + 0.8, top + 0.8, Pal.tomato, 118);
    // lamp
    final lx = o.x1 - 0.6, ly = o.y0 + 0.5;
    flatCircle(c, lx, ly, 0.3, top, ink, 119, 0.4);
    line3(c, [lx, ly, top], [lx - 0.2, ly + 0.1, top + 1.2], 1.1);
    final lp = iso(lx - 0.2, ly + 0.1, top + 1.3);
    final shadeP = wobblePath([
      lp + Offset(-t * 0.55, t * 0.25),
      lp + Offset(-t * 0.15, -t * 0.35),
      lp + Offset(t * 0.25, -t * 0.35),
      lp + Offset(t * 0.5, t * 0.25),
    ], 120, t);
    c.drawPath(shadeP, fillPaint(Pal.mustard));
    stroke(c, shadeP, 0.8);
    // microphone
    const mx = LayoutSpots.micX, my = LayoutSpots.micY;
    flatCircle(c, mx, my, 0.32, top, ink, 121, 0.4);
    line3(c, [mx, my, top], [mx, my, top + 0.8], 1.1);
    final hp = iso(mx, my, top + 1.15);
    final head = RRect.fromRectAndRadius(
        Rect.fromCenter(center: hp, width: t * 0.52, height: t * 0.8), Radius.circular(t * 0.26));
    c.drawRRect(head, fillPaint(rec ? const Color(0xFFF09585) : const Color(0xFFD6DDE2)));
    c.drawRRect(head, inkPaint(math.max(1.2, t * 0.07)));
    for (var i = 0; i < 3; i++) {
      final y = hp.dy - t * 0.18 + i * t * 0.15;
      c.drawLine(Offset(hp.dx - t * 0.16, y), Offset(hp.dx + t * 0.16, y), inkPaint(math.max(1, t * 0.03)));
    }
    // mug
    box(c, o.x0 + 0.4, o.y1 - 0.8, top, o.x0 + 0.8, o.y1 - 0.4, top + 0.45, Pal.cream, 122);
  }

  void _crate(Canvas c, int n) {
    const o = RoomLayout.crate;
    final r = SeededRandom(9);
    box(c, o.x0, o.y0, 0, o.x1, o.y1, o.z1, Pal.woodLight, 131);
    for (final z in [0.42, 0.86]) {
      line3(c, [o.x0, o.y1, z], [o.x1, o.y1, z], 0.6);
      line3(c, [o.x1, o.y0, z], [o.x1, o.y1, z], 0.6);
    }
    for (var i = 0; i < math.min(n, 5); i++) {
      final x = o.x0 + 0.3 + i * 0.24, y = o.y0 + 0.3 + r.next() * 0.5, tilt = (r.next() - 0.5) * 0.3;
      quad(c, [x, y, o.z1], [x, y + 0.7, o.z1], [x + tilt, y + 0.7, o.z1 + 0.55], [x + tilt, y, o.z1 + 0.55],
          i.isOdd ? Pal.note : Pal.cream, 132 + i, 0.6);
    }
    quad(c, [o.x0 + 0.35, o.y1 + 0.01, 0.25], [o.x1 - 0.35, o.y1 + 0.01, 0.25], [o.x1 - 0.35, o.y1 + 0.01, 1.0],
        [o.x0 + 0.35, o.y1 + 0.01, 1.0], Pal.cream, 139, 0.6);
    final lp = iso((o.x0 + o.x1) / 2, o.y1, 0.62);
    final tp = TextPainter(
      text: TextSpan(text: '$n', style: TextStyle(fontFamily: handFont, color: ink, fontSize: t * 0.6)),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(lp.dx, lp.dy);
    c.transform(Float64List4.skewY(0.577));
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  void _bowl(Canvas c, int treats) {
    const x = 8.4, y = 6.4;
    flatCircle(c, x, y, 0.5, 0.01, shade(Pal.blue, -0.15), 151, 0.8);
    flatCircle(c, x, y, 0.55, 0.3, Pal.blue, 152, 0.8);
    for (var i = 0; i < math.min(treats, 3) + 1; i++) {
      final p = iso(x - 0.15 + i * 0.15, y - 0.1 + (i.isOdd ? 0.15 : 0), 0.4);
      final fish = Rect.fromCenter(center: p, width: t * 0.44, height: t * 0.2);
      c.drawOval(fish, fillPaint(const Color(0xFFF29E6B)));
      c.drawOval(fish, inkPaint(math.max(1, t * 0.04)));
    }
  }

  void _mailbox(Canvas c) {
    // body is cached; only the flag moves
    _cached(c, 'mailbox', (c) => _mailboxBody(c));
    const o = RoomLayout.mailbox;
    final fp = iso(o.x0 + 0.5, o.y1 + 0.02, 2.8);
    c.save();
    c.translate(fp.dx, fp.dy);
    c.rotate(mailFlagUp ? -math.pi / 2 + 0.15 * math.sin(time * 5) : 0.35);
    final flag = Path()
      ..addRect(Rect.fromLTWH(-t * 0.06, -t * 0.06, t * 0.9, t * 0.12))
      ..addRect(Rect.fromLTWH(t * 0.6, -t * 0.06, t * 0.32, t * 0.36));
    c.drawPath(flag, fillPaint(Pal.mustard));
    stroke(c, flag, 0.6);
    c.restore();
  }

  void _mailboxBody(Canvas c) {
    const o = RoomLayout.mailbox;
    final cx = (o.x0 + o.x1) / 2, cy = (o.y0 + o.y1) / 2, hy = (o.y1 - o.y0) / 2;
    box(c, cx - 0.14, cy - 0.14, 0, cx + 0.14, cy + 0.14, 2.4, Pal.woodDark, 102);
    box(c, o.x0, o.y0, 2.4, o.x1, o.y1, 2.95, Pal.tomato, 103);
    const rz = 2.95, rh = 0.5, steps = 7;
    for (var i = 0; i < steps; i++) {
      final a0 = math.pi * i / steps, a1 = math.pi * (i + 1) / steps;
      final yA = cy + math.cos(a0) * hy, yB = cy + math.cos(a1) * hy;
      final zA = rz + math.sin(a0) * rh, zB = rz + math.sin(a1) * rh;
      c.drawPath(Path()..addPolygon([iso(o.x0, yA, zA), iso(o.x1, yA, zA), iso(o.x1, yB, zB), iso(o.x0, yB, zB)], true),
          fillPaint(shade(Pal.tomato, i < 3 ? -0.05 : 0.08)));
    }
    final back = Path();
    for (var i = 0; i <= 12; i++) {
      final a = math.pi * i / 12;
      final q = iso(o.x0, cy + math.cos(a) * hy, rz + math.sin(a) * rh);
      i == 0 ? back.moveTo(q.dx, q.dy) : back.lineTo(q.dx, q.dy);
    }
    stroke(c, back, 0.9);
    final end = Path();
    for (var i = 0; i <= 12; i++) {
      final a = math.pi * i / 12;
      final q = iso(o.x1, cy + math.cos(a) * hy, rz + math.sin(a) * rh);
      i == 0 ? end.moveTo(q.dx, q.dy) : end.lineTo(q.dx, q.dy);
    }
    final e1 = iso(o.x1, o.y0, 2.4), e2 = iso(o.x1, o.y1, 2.4);
    end
      ..lineTo(e1.dx, e1.dy)
      ..lineTo(e2.dx, e2.dy)
      ..close();
    c.drawPath(end, fillPaint(shade(Pal.tomato, -0.15)));
    stroke(c, end, 0.9);
    // a letter peeking out
    final lp = iso(o.x1 + 0.01, cy, 3.1);
    c.save();
    c.translate(lp.dx, lp.dy);
    c.rotate(-0.5);
    final letter = Rect.fromLTWH(-t * 0.3, -t * 0.2, t * 0.6, t * 0.38);
    c.drawRect(letter, fillPaint(Pal.cream));
    c.drawRect(letter, inkPaint(math.max(1.2, t * 0.05)));
    c.restore();
  }

  @override
  bool shouldRepaint(RoomPainter old) => true;
}

/// Small 4x4 skew helper (Canvas.transform wants a column-major Float64List).
class Float64List4 {
  static Float64List skewY(double k) => Float64List.fromList([1, k, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
}

/// Where the microphone sits on the desk (shared with the pet controller).
class LayoutSpots {
  static const micX = 6.05; // desk.x0 + 1.75
  static const micY = 1.1; // desk.y1 - 0.5
}
