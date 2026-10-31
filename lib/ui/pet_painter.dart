import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../pet_controller.dart';
import 'room_painter.dart';

/// Draws the pet (any character) in its current pose.
/// Local units: the pet is 24 units tall, origin between its feet,
/// +x is the way it faces (the canvas is mirrored when facing left).
class PetPainter extends CustomPainter {
  PetPainter({
    required this.character,
    required this.foot,
    required this.height,
    required this.mood,
    required this.held,
    required this.facingLeft,
    required this.talking,
    required this.time,
    required this.level,
  });

  final PetCharacter character;
  final Offset foot;
  final double height;
  final PetMood mood;
  final HeldItem held;
  final bool facingLeft;
  final bool talking;
  final double time;
  final double level;

  late double s; // one local unit in pixels

  Offset p(double x, double y) => Offset(x * s, y * s);
  Paint line([double w = 0.55]) => inkPaint(w * s);

  void blob(Canvas c, Path path, Color color, [double w = 0.55]) {
    c.drawPath(path, fillPaint(color));
    c.drawPath(path, line(w));
  }

  Path oval(double cx, double cy, double w, double h) =>
      Path()..addOval(Rect.fromCenter(center: p(cx, cy), width: w * s, height: h * s));

  @override
  void paint(Canvas canvas, Size size) {
    s = height / 24;
    final t = time;
    final ch = character;

    // ---- body motion ----
    double bob = 0, squash = 1 + 0.02 * math.sin(t * 2.2), lean = 0;
    switch (mood) {
      case PetMood.walking:
        bob = (math.sin(t * 11)).abs() * 1.3;
        lean = 0.05;
      case PetMood.happy:
        bob = (math.sin(t * 7)).abs() * 3;
      case PetMood.searching:
      case PetMood.digging:
        bob = (math.sin(t * 9)).abs() * 0.8;
      case PetMood.listening:
        squash = 1 + 0.04 * level;
      case PetMood.sad:
        squash = 0.97;
      case PetMood.dancing:
        bob = (math.sin(t * 6)).abs() * 2.2;
        lean = math.sin(t * 3) * 0.12;
      default:
        break;
    }

    // shadow
    canvas.drawOval(
      Rect.fromCenter(center: foot + Offset(0, 0.4 * s), width: (17 - bob) * s, height: 3.4 * s),
      fillPaint(ink.withValues(alpha: 0.15)),
    );

    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    if (facingLeft) canvas.scale(-1, 1);

    // flying books are drawn in front of the shelf, behind the pet
    if (mood == PetMood.searching) _flyingBooks(canvas, t);
    if (mood == PetMood.digging) _flyingBooks(canvas, t, papers: true);

    canvas.translate(0, -bob * s);
    canvas.rotate(lean);
    canvas.scale(1, squash);

    _tail(canvas, ch, t);
    if (ch.spiky) _spikes(canvas, ch);
    _ears(canvas, ch, t, back: true);

    // feet
    final walk = mood == PetMood.walking ? math.sin(t * 11) : 0.0;
    blob(canvas, oval(-4.5 + walk * 1.2, -1.1, 5.5, 2.8), ch.body);
    blob(canvas, oval(4.5 - walk * 1.2, -1.1, 5.5, 2.8), ch.body);

    // body: a round, slightly pear-shaped potato
    final body = Path()
      ..moveTo(0, -20.5 * s)
      ..cubicTo(7.5 * s, -20.5 * s, 10.5 * s, -14 * s, 10.3 * s, -8 * s)
      ..cubicTo(10.1 * s, -2.5 * s, 6 * s, -0.6 * s, 0, -0.6 * s)
      ..cubicTo(-6 * s, -0.6 * s, -10.1 * s, -2.5 * s, -10.3 * s, -8 * s)
      ..cubicTo(-10.5 * s, -14 * s, -7.5 * s, -20.5 * s, 0, -20.5 * s)
      ..close();
    blob(canvas, body, ch.body);
    canvas.save();
    canvas.clipPath(body);
    canvas.drawPath(oval(0, -5.5, 13, 10), fillPaint(ch.belly));
    if (ch.patch != null) {
      final stripe = inkPaint(1.1 * s, ch.patch!)..strokeCap = StrokeCap.round;
      canvas.drawLine(p(-1.6, -20.5), p(-1.2, -18), stripe);
      canvas.drawLine(p(0.4, -20.8), p(0.4, -17.8), stripe);
      canvas.drawLine(p(2.4, -20.5), p(2, -18), stripe);
      canvas.drawLine(p(10.5, -11), p(8.2, -10.5), stripe);
      canvas.drawLine(p(-10.5, -11), p(-8.2, -10.5), stripe);
    }
    canvas.restore();
    canvas.drawPath(body, line());

    _ears(canvas, ch, t, back: false);
    _face(canvas, ch, t);
    _accessory(canvas, ch);
    _arms(canvas, ch, t);

    canvas.restore();

    // effects in screen space (not mirrored)
    _effects(canvas, t);
  }

  void _tail(Canvas c, PetCharacter ch, double t) {
    final sway = math.sin(t * (mood == PetMood.happy ? 9 : 2.5)) * 0.18;
    switch (ch.tail) {
      case TailStyle.curl:
        c.save();
        c.translate(-8 * s, -4 * s);
        c.rotate(sway);
        final tail = Path()
          ..moveTo(0, 0)
          ..cubicTo(-6 * s, 0, -8 * s, -6 * s, -5 * s, -9 * s)
          ..cubicTo(-3.5 * s, -10.5 * s, -2 * s, -9 * s, -3.4 * s, -8 * s);
        c.drawPath(tail, inkPaint(3.6 * s, ink));
        c.drawPath(tail, inkPaint(2.4 * s, ch.body));
        c.restore();
      case TailStyle.fluffy:
        c.save();
        c.translate(-8.5 * s, -6 * s);
        c.rotate(sway * 2 - 0.5);
        blob(c, oval(-3, -2, 7, 4.5), ch.body);
        c.restore();
      case TailStyle.puff:
        blob(c, oval(-9.5, -4, 4.6, 4.6), ch.belly);
      case TailStyle.none:
        break;
    }
  }

  void _spikes(Canvas c, PetCharacter ch) {
    final dark = Color.lerp(ch.body, ink, 0.35)!;
    for (var i = 0; i <= 10; i++) {
      final a = math.pi + i * math.pi / 10;
      final base = Offset(math.cos(a) * 9.5, -10 + math.sin(a) * 9.5);
      final tip = Offset(math.cos(a) * 13, -10 + math.sin(a) * 13);
      final side = Offset(-math.sin(a), math.cos(a)) * 1.8;
      final spike = Path()
        ..moveTo((base.dx + side.dx) * s, (base.dy + side.dy) * s)
        ..lineTo(tip.dx * s, tip.dy * s)
        ..lineTo((base.dx - side.dx) * s, (base.dy - side.dy) * s)
        ..close();
      blob(c, spike, dark, 0.4);
    }
  }

  void _ears(Canvas c, PetCharacter ch, double t, {required bool back}) {
    final perk = mood == PetMood.listening ? -1.0 : (mood == PetMood.sad ? 1.5 : 0.0);
    switch (ch.ears) {
      case EarStyle.pointy:
        if (!back) return;
        for (final d in [-1.0, 1.0]) {
          final ear = Path()
            ..moveTo(d * 3 * s, -19.4 * s)
            ..lineTo(d * 7.2 * s, (-24.5 + perk) * s)
            ..lineTo(d * 8.6 * s, -15.5 * s)
            ..close();
          blob(c, ear, ch.body);
          final inner = Path()
            ..moveTo(d * 4.6 * s, -18.8 * s)
            ..lineTo(d * 7 * s, (-22.4 + perk) * s)
            ..lineTo(d * 7.7 * s, -16.8 * s)
            ..close();
          c.drawPath(inner, fillPaint(ch.innerEar));
        }
      case EarStyle.long:
        if (!back) return;
        for (final d in [-1.0, 1.0]) {
          c.save();
          c.translate(d * 3.2 * s, -19 * s);
          c.rotate(d * (0.18 + 0.05 * math.sin(t * 2)) + (mood == PetMood.sad ? d * 0.8 : 0));
          blob(c, oval(0, -5.5, 4.4, 12), ch.body);
          c.drawPath(oval(0, -5.5, 2, 8.5), fillPaint(ch.innerEar));
          c.restore();
        }
      case EarStyle.floppy:
        if (back) return;
        for (final d in [-1.0, 1.0]) {
          c.save();
          c.translate(d * 8 * s, -16 * s);
          c.rotate(d * (0.35 + 0.08 * math.sin(t * 3)) - d * perk * 0.1);
          blob(c, oval(d * 1.2, 4, 4.6, 9.5), ch.patch ?? ch.body);
          c.restore();
        }
      case EarStyle.round:
        if (!back) return;
        for (final d in [-1.0, 1.0]) {
          blob(c, oval(d * 6.4, -18.4 + perk * 0.5, 5.4, 5.4), ch.body);
          c.drawPath(oval(d * 6.4, -18.2 + perk * 0.5, 2.8, 2.8), fillPaint(ch.innerEar));
        }
    }
  }

  void _face(Canvas c, PetCharacter ch, double t) {
    final blink = (t % 3.7) < 0.12 && mood != PetMood.happy;
    double lookX = 0.6, lookY = 0;
    if (mood == PetMood.thinking) {
      lookY = -0.9;
      lookX = 0.9;
    }
    if (mood == PetMood.reading || mood == PetMood.dropping) lookY = 0.7;
    final eyeY = -12.4 + lookY;

    // blush
    for (final d in [-1.0, 1.0]) {
      c.drawPath(oval(d * 6.3 + lookX * 0.3, -9.6, 3.2, 1.8),
          fillPaint(const Color(0xFFF08A7E).withValues(alpha: 0.55)));
    }

    for (final d in [-1.0, 1.0]) {
      final e = p(d * 3.6 + lookX, eyeY);
      if (mood == PetMood.happy) {
        c.drawArc(Rect.fromCenter(center: e, width: 2.6 * s, height: 2.2 * s), math.pi, math.pi,
            false, line(0.6));
      } else if (mood == PetMood.sad) {
        c.drawLine(e + p(-1.1, -0.2), e + p(1.1, 0.4 * d), line(0.6));
      } else if (blink) {
        c.drawLine(e + p(-1, 0), e + p(1, 0), line(0.6));
      } else {
        c.drawCircle(e, 1.05 * s, fillPaint(ink));
        c.drawCircle(e + p(0.35, -0.35), 0.35 * s, fillPaint(Colors.white));
      }
    }

    // nose / mouth
    final m = p(lookX * 0.8, -9.9 + lookY * 0.3);
    if (ch.ears == EarStyle.floppy || ch.spiky) {
      c.drawOval(Rect.fromCenter(center: m + p(0, -0.9), width: 1.8 * s, height: 1.2 * s),
          fillPaint(ink));
    }
    final mouthOpen = talking
        ? (0.3 + 0.7 * (math.sin(t * 15) * 0.5 + 0.5))
        : (mood == PetMood.happy ? 0.8 : 0.0);
    if (mouthOpen > 0.15) {
      final r = Rect.fromCenter(center: m + p(0, 0.6), width: 2.2 * s, height: (0.6 + 1.6 * mouthOpen) * s);
      c.drawOval(r, fillPaint(const Color(0xFFB8485A)));
      c.drawOval(r, line(0.4));
    } else if (mood == PetMood.sad) {
      c.drawArc(Rect.fromCenter(center: m + p(0, 1), width: 2.4 * s, height: 1.6 * s), math.pi * 1.1,
          math.pi * 0.8, false, line(0.45));
    } else {
      // cute "w" mouth
      final w = Path()
        ..moveTo(m.dx - 1.4 * s, m.dy)
        ..quadraticBezierTo(m.dx - 0.7 * s, m.dy + 0.9 * s, m.dx, m.dy)
        ..quadraticBezierTo(m.dx + 0.7 * s, m.dy + 0.9 * s, m.dx + 1.4 * s, m.dy);
      c.drawPath(w, line(0.4));
    }
  }

  void _accessory(Canvas c, PetCharacter ch) {
    // a little bow on the head, like a gift
    final b = p(4.2, -18.6);
    c.save();
    c.translate(b.dx, b.dy);
    c.rotate(0.25);
    final bow = Path()
      ..moveTo(0, 0)
      ..lineTo(-2.6 * s, -1.6 * s)
      ..lineTo(-2.6 * s, 1.6 * s)
      ..close()
      ..moveTo(0, 0)
      ..lineTo(2.6 * s, -1.6 * s)
      ..lineTo(2.6 * s, 1.6 * s)
      ..close();
    blob(c, bow, ch.accessory, 0.4);
    c.drawCircle(Offset.zero, 0.8 * s, fillPaint(ch.accessory));
    c.drawCircle(Offset.zero, 0.8 * s, line(0.35));
    c.restore();
  }

  void _arms(Canvas c, PetCharacter ch, double t) {
    void arm(double x, double y, double angle) {
      c.save();
      c.translate(x * s, y * s);
      c.rotate(angle);
      blob(c, oval(0, 1.6, 3, 4.4), ch.body, 0.5);
      c.restore();
    }

    switch (mood) {
      case PetMood.searching:
      case PetMood.digging:
        final a = math.sin(t * 9);
        arm(7.5, -11, -2.4 + a * 0.4);
        arm(-7.5, -11, 2.4 + a * 0.4);
      case PetMood.reading:
        if (held == HeldItem.letter) {
          _letter(c, Offset(0, -6.2), 1.0, t);
        } else if (held == HeldItem.note) {
          _note(c, Offset(0, -6.5), 1.0);
        } else {
          _openBook(c);
        }
        arm(6.5, -7.5, 0.6);
        arm(-6.5, -7.5, -0.6);
      case PetMood.mail:
        if (held == HeldItem.letter) {
          _letter(c, Offset(6, -9 + math.sin(t * 6) * 0.6), 0.9, t);
          arm(7.5, -8.5, -0.9);
        } else {
          arm(8.5, -10, -1.9 + math.sin(t * 10) * 0.5); // rummaging
        }
        arm(-8.5, -6, 0.3);
      case PetMood.listening:
        _heldMic(c);
        arm(7.5, -8.8, -0.9);
        arm(-8.5, -6, 0.3);
      case PetMood.dropping:
        final ph = (t % 0.9) / 0.9;
        _note(c, Offset(11 + ph * 3, -9 + ph * 10), 0.85, rotate: ph * 1.2);
        arm(8, -10, -1.5);
        arm(-8.5, -6, 0.3);
      case PetMood.walking:
        if (held == HeldItem.note) _note(c, Offset(7.5, -8), 0.8);
        if (held == HeldItem.book) _closedBook(c, Offset(7.5, -8));
        if (held == HeldItem.letter) _letter(c, Offset(7.5, -8), 0.8, t);
        if (held == HeldItem.gift) _gift(c, Offset(7.5, -9), 0.9);
        final sw = math.sin(t * 11) * 0.35;
        arm(8.5, -7, sw);
        arm(-8.5, -7, -sw);
      case PetMood.thinking:
        if (held == HeldItem.note) _note(c, Offset(7.5, -8), 0.8);
        arm(7.5, -9.5, -2.2); // paw on chin
        arm(-8.5, -6.5, 0.25);
      case PetMood.happy:
        if (held == HeldItem.gift) {
          _gift(c, Offset(0, -15 + math.sin(t * 5) * 0.8), 1.1); // holding it up
          arm(6.5, -12, -2.7);
          arm(-6.5, -12, 2.7);
        } else {
          final w = math.sin(t * 7) * 0.3;
          arm(8.5, -10, -2.3 + w);
          arm(-8.5, -10, 2.3 - w);
        }
      case PetMood.dancing:
        final w = math.sin(t * 6);
        arm(8.5, -9, -1.6 + w * 0.9);
        arm(-8.5, -9, 1.6 + w * 0.9);
      default:
        arm(8.6, -6.4, 0.25);
        arm(-8.6, -6.4, -0.25);
    }
  }

  void _openBook(Canvas c) {
    final l = Path()
      ..moveTo(0, -3.5 * s)
      ..quadraticBezierTo(-3 * s, -4.6 * s, -6.4 * s, -4 * s)
      ..lineTo(-6.4 * s, -10.6 * s)
      ..quadraticBezierTo(-3 * s, -11.2 * s, 0, -10 * s)
      ..close();
    final r = Path()
      ..moveTo(0, -3.5 * s)
      ..quadraticBezierTo(3 * s, -4.6 * s, 6.4 * s, -4 * s)
      ..lineTo(6.4 * s, -10.6 * s)
      ..quadraticBezierTo(3 * s, -11.2 * s, 0, -10 * s)
      ..close();
    final cover = Rect.fromLTRB(-7 * s, -10.4 * s, 7 * s, -3.4 * s);
    c.drawRRect(RRect.fromRectAndRadius(cover, Radius.circular(0.6 * s)), fillPaint(const Color(0xFFD9574A)));
    c.drawRRect(RRect.fromRectAndRadius(cover, Radius.circular(0.6 * s)), line(0.45));
    blob(c, l, const Color(0xFFFFFBF0), 0.4);
    blob(c, r, const Color(0xFFFFFBF0), 0.4);
    final txt = inkPaint(0.25 * s, ink.withValues(alpha: 0.45));
    for (var i = 0; i < 3; i++) {
      final y = (-8.6 + i * 1.5) * s;
      c.drawLine(Offset(-5.4 * s, y), Offset(-1.2 * s, y), txt);
      c.drawLine(Offset(1.2 * s, y), Offset(5.4 * s, y), txt);
    }
  }

  void _closedBook(Canvas c, Offset at) {
    final r = Rect.fromCenter(center: p(at.dx, at.dy), width: 4 * s, height: 5.4 * s);
    c.drawRect(r, fillPaint(const Color(0xFFD9574A)));
    c.drawRect(r, line(0.4));
    c.drawLine(r.topLeft + p(0.8, 0), r.bottomLeft + p(0.8, 0), line(0.3));
  }

  void _letter(Canvas c, Offset at, double k, double t) {
    final r = Rect.fromCenter(center: p(at.dx, at.dy), width: 8 * s * k, height: 5.4 * s * k);
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(0.4 * s)), fillPaint(const Color(0xFFFFFBF0)));
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(0.4 * s)), line(0.4));
    c.drawPath(
        Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.center.dx, r.center.dy + 0.4 * s)
          ..lineTo(r.right, r.top),
        line(0.35));
    // heart seal
    c.drawCircle(r.center + p(0, 0.4), 0.9 * s * k, fillPaint(const Color(0xFFD9574A)));
  }

  /// A little wrapped present: whatever the pet found to cheer you up.
  void _gift(Canvas c, Offset at, double k) {
    final r = Rect.fromCenter(center: p(at.dx, at.dy), width: 6 * s * k, height: 5 * s * k);
    c.drawRect(r, fillPaint(const Color(0xFF8FB8DE)));
    c.drawRect(r, line(0.4));
    final ribbon = fillPaint(const Color(0xFFF07A8A));
    c.drawRect(Rect.fromCenter(center: r.center, width: 1.2 * s * k, height: r.height), ribbon);
    c.drawRect(Rect.fromCenter(center: r.center, width: r.width, height: 1.0 * s * k), ribbon);
    final top = Offset(r.center.dx, r.top);
    for (final dir in [-1.0, 1.0]) {
      c.drawOval(Rect.fromCenter(center: top + Offset(dir * 1.3 * s * k, -0.9 * s * k), width: 2.4 * s * k, height: 1.6 * s * k), ribbon);
      c.drawOval(Rect.fromCenter(center: top + Offset(dir * 1.3 * s * k, -0.9 * s * k), width: 2.4 * s * k, height: 1.6 * s * k), line(0.3));
    }
  }

  void _note(Canvas c, Offset at, double k, {double rotate = 0}) {
    c.save();
    c.translate(at.dx * s, at.dy * s);
    c.rotate(rotate);
    final r = Rect.fromCenter(center: Offset.zero, width: 5.6 * s * k, height: 6.6 * s * k);
    c.drawRect(r, fillPaint(const Color(0xFFFFF3B0)));
    c.drawRect(r, line(0.35));
    final txt = inkPaint(0.25 * s, ink.withValues(alpha: 0.5));
    for (var i = 0; i < 3; i++) {
      final y = r.top + (1.6 + i * 1.5) * s * k;
      c.drawLine(Offset(r.left + 0.8 * s, y), Offset(r.right - 0.8 * s, y), txt);
    }
    c.restore();
  }

  void _heldMic(Canvas c) {
    c.save();
    c.translate(10 * s, -12 * s);
    c.rotate(0.35);
    final handle = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p(0, 3), width: 1.6 * s, height: 6 * s), Radius.circular(0.6 * s));
    blob(c, Path()..addRRect(handle), const Color(0xFF4A4A55), 0.35);
    blob(c, oval(0, -1, 3.8, 3.8), const Color(0xFFCFD6DA), 0.45);
    c.restore();
  }

  /// Books fly off the shelf while answering; note papers fly out of the
  /// notes box while searching memories.
  void _flyingBooks(Canvas c, double t, {bool papers = false}) {
    final colors = papers
        ? const [Pal.note, Pal.cream, Pal.note, Color(0xFFFFFFFF)]
        : const [Pal.blue, Pal.mustard, Pal.sage, Pal.lilac];
    for (var i = 0; i < 4; i++) {
      final ph = ((t * 0.75) + i / 4) % 1.0;
      // arc from the shelf (in front, up high) over the pet's head and down behind
      final x = 13 - ph * 26;
      final y = -24 - math.sin(ph * math.pi) * 10 + ph * 16;
      c.save();
      c.translate(x * s, y * s);
      c.rotate(ph * math.pi * 2.2 + i);
      final r = Rect.fromCenter(center: Offset.zero, width: (papers ? 4.2 : 3.6) * s, height: (papers ? 4.6 : 4.8) * s);
      final alpha = ph < 0.85 ? 1.0 : (1 - ph) / 0.15;
      c.drawRect(r, fillPaint(colors[i].withValues(alpha: alpha)));
      c.drawRect(r, inkPaint(0.35 * s, ink.withValues(alpha: alpha)));
      if (papers) {
        final line = inkPaint(0.22 * s, ink.withValues(alpha: alpha * 0.45));
        for (var k = 0; k < 3; k++) {
          final y = r.top + (1.3 + k * 1.2) * s;
          c.drawLine(Offset(r.left + 0.7 * s, y), Offset(r.right - 0.7 * s, y), line);
        }
      }
      c.restore();
    }
  }

  void _effects(Canvas c, double t) {
    final head = foot + Offset(0, -24 * s);
    switch (mood) {
      case PetMood.thinking:
        for (var i = 0; i < 3; i++) {
          final on = ((t * 2.5).floor() % 4) > i;
          c.drawCircle(head + Offset((i - 1) * 2.4 * s, -1.5 * s), 0.9 * s,
              fillPaint(ink.withValues(alpha: on ? 0.8 : 0.2)));
        }
      case PetMood.searching:
      case PetMood.digging:
        for (var i = 0; i < 3; i++) {
          final ph = (t * 1.3 + i * 0.33) % 1.0;
          final o = head + Offset((facingLeft ? -1 : 1) * (6 + i * 3) * s, (-2 - ph * 5) * s);
          _sparkle(c, o, (1.6 - ph) * s, const Color(0xFFFFD66B).withValues(alpha: 1 - ph));
        }
      case PetMood.happy:
        for (var i = 0; i < 2; i++) {
          final ph = (t * 0.9 + i * 0.5) % 1.0;
          _heart(c, head + Offset((i == 0 ? -7 : 7) * s, (-ph * 7) * s), 1.6 * s,
              const Color(0xFFF07A8A).withValues(alpha: 1 - ph));
        }
      case PetMood.dancing:
        for (var i = 0; i < 3; i++) {
          final ph = (t * 0.7 + i / 3) % 1.0;
          final o = head + Offset((i - 1) * 7 * s + math.sin(ph * 6) * 1.5 * s, (2 - ph * 10) * s);
          _musicNote(c, o, 1.3 * s, ink.withValues(alpha: (1 - ph) * 0.85));
        }
      case PetMood.sad:
        c.drawPath(
            Path()
              ..moveTo(head.dx + 9 * s, head.dy + 6 * s)
              ..quadraticBezierTo(head.dx + 10.4 * s, head.dy + 8.6 * s, head.dx + 9 * s, head.dy + 9 * s)
              ..quadraticBezierTo(head.dx + 7.6 * s, head.dy + 8.6 * s, head.dx + 9 * s, head.dy + 6 * s),
            fillPaint(const Color(0xFF8CC8E8)));
      case PetMood.listening:
        final dir = facingLeft ? -1.0 : 1.0;
        final mic = foot + Offset(dir * 12 * s, -14 * s);
        for (var i = 0; i < 3; i++) {
          final r = (3 + i * 2.2 + level * 2) * s;
          c.drawArc(Rect.fromCircle(center: mic, radius: r), dir > 0 ? -0.6 : math.pi - 0.6, 1.2, false,
              inkPaint(0.45 * s, const Color(0xFFD9574A).withValues(alpha: (0.25 + level * 0.75) * (1 - i * 0.25))));
        }
      default:
        break;
    }
  }

  void _musicNote(Canvas c, Offset o, double r, Color color) {
    c.drawOval(Rect.fromCenter(center: o, width: r * 1.6, height: r * 1.2), fillPaint(color));
    final stem = inkPaint(r * 0.32, color);
    c.drawLine(o + Offset(r * 0.7, 0), o + Offset(r * 0.7, -r * 2.6), stem);
    c.drawLine(o + Offset(r * 0.7, -r * 2.6), o + Offset(r * 1.6, -r * 2.0), stem);
  }

  void _sparkle(Canvas c, Offset o, double r, Color color) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r);
    c.drawPath(path, fillPaint(color));
  }

  void _heart(Canvas c, Offset o, double r, Color color) {
    final path = Path()
      ..moveTo(o.dx, o.dy + r)
      ..cubicTo(o.dx - 2 * r, o.dy - 0.2 * r, o.dx - 0.9 * r, o.dy - 1.6 * r, o.dx, o.dy - 0.5 * r)
      ..cubicTo(o.dx + 0.9 * r, o.dy - 1.6 * r, o.dx + 2 * r, o.dy - 0.2 * r, o.dx, o.dy + r);
    c.drawPath(path, fillPaint(color));
  }

  @override
  bool shouldRepaint(PetPainter old) => true;
}
