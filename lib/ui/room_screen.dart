import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/character.dart';
import '../pet_controller.dart';
import 'app_sheet.dart';
import 'ask_sheet.dart';
import 'cheer_sheet.dart';
import 'message_sheet.dart';
import 'doodle.dart';
import 'notes_page.dart';
import 'pet_painter.dart';
import 'record_panel.dart';
import 'room_layout.dart';
import 'room_painter.dart';
import 'settings_screen.dart';
import 'speech_bubble.dart';
import 'wardrobe_sheet.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.pet});
  final PetController pet;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  StreamSubscription<PetEvent>? _events;

  PetController get pet => widget.pet;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      final step = dt > 0.1 ? 0.1 : dt;
      _time += step;
      pet.tick(step);
      setState(() {});
    })
      ..start();
    _events = pet.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _events?.cancel();
    super.dispose();
  }

  void _onEvent(PetEvent e) {
    if (!mounted) return;
    switch (e) {
      case PetEvent.openSettings:
        _openSettings();
      case PetEvent.openMailSettings:
        _openSettings(scrollToMail: true);
      case PetEvent.openNotes:
        _openNotes();
      case PetEvent.openFind:
        _openNotes(search: true);
      case PetEvent.composeMessage:
        final d = pet.pendingDraft;
        if (d != null) showMessageSheet(context, pet, d);
      case PetEvent.getApp:
        final name = pet.pendingAppName;
        if (name != null) showAppSheet(context, pet, name);
      case PetEvent.cheer:
        final item = pet.pendingCheer;
        if (item != null) showCheerSheet(context, pet, item);
      case PetEvent.support:
        showSupportSheet(context);
      case PetEvent.newTreatFriend:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A new friend unlocked! Tap the wardrobe to meet them.'),
        ));
    }
  }

  void _openNotes({bool search = false}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesPage(pet: pet, focusSearch: search)));
  }

  void _openSettings({bool scrollToMail = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(pet: pet, focusEmail: scrollToMail),
    ));
  }

  void _onTap(Offset local, RoomLayout l) {
    // the pet first, since it walks in front of everything
    final foot = l.at(pet.position);
    final petRect = Rect.fromLTRB(foot.dx - 1.3 * l.t, foot.dy - l.petHeight, foot.dx + 1.3 * l.t, foot.dy + 0.3 * l.t);
    if (petRect.contains(local)) {
      // tap the pet to talk to it
      if (pet.busy || pet.recording) {
        pet.pet();
      } else {
        showAskSheet(context, pet);
      }
      return;
    }
    const deskTap = WorldBox(4.3, 0, 7.6, 1.6, 3.6);
    if (l.screenRect(deskTap).contains(local)) {
      pet.toggleRecording();
    } else if (pet.recording) {
      // ignore stray taps while recording so the note isn't interrupted
      return;
    } else if (l.screenRect(RoomLayout.shelf, 0).contains(local)) {
      showAskSheet(context, pet);
    } else if (l.screenRect(RoomLayout.mailbox).contains(local)) {
      pet.checkMail();
    } else if (l.screenRect(RoomLayout.crate).contains(local)) {
      _openNotes();
    } else if (l.screenRect(RoomLayout.wardrobe, 0).contains(local)) {
      showWardrobeSheet(context, pet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final character = pet.character;
    final recordingUi = pet.recState != RecState.idle;
    return Scaffold(
      backgroundColor: Pal.sky,
      // The keyboard (on the review card) must not squash the room.
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                _Counter(icon: '🐟', value: pet.settings.treats, label: 'Fish treats', seed: 3),
                const SizedBox(width: 10),
                _Counter(icon: '📝', value: pet.notes.notes.length, label: 'Notes in the box', seed: 7),
                const Spacer(),
                DoodleButton(
                  tooltip: 'Friends',
                  onTap: () => showWardrobeSheet(context, pet),
                  child: const Icon(Icons.checkroom_rounded, color: ink),
                ),
                const SizedBox(width: 10),
                DoodleButton(
                  tooltip: 'Settings',
                  onTap: _openSettings,
                  child: const Icon(Icons.settings_rounded, color: ink),
                ),
              ]),
            ),
            _Banner(text: pet.status),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                final l = RoomLayout(size);
                final foot = l.at(pet.position);
                final petPainter = PetPainter(
                  character: character,
                  foot: foot,
                  height: l.petHeight,
                  mood: pet.mood,
                  held: pet.held,
                  facingLeft: pet.facingLeft,
                  talking: pet.talking,
                  time: _time,
                  level: pet.voice.level.value,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d.localPosition, l),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: RoomPainter(
                            time: _time,
                            noteCount: pet.notes.notes.length,
                            treats: pet.settings.treats,
                            mailFlagUp: pet.mood == PetMood.mail,
                            recording: pet.recording,
                            searching: pet.mood == PetMood.searching,
                            pet: petPainter,
                            petWorld: pet.position,
                          ),
                        ),
                      ),
                      if (pet.bubble != null)
                        SpeechBubble(
                          text: pet.bubble!,
                          fromUser: pet.bubbleIsUser,
                          anchor: foot - Offset(0, l.petHeight * 1.1),
                          below: foot + const Offset(0, 8),
                          area: size,
                          onClose: pet.busy ? null : () => setState(() => pet.bubble = null),
                        ),
                    ],
                  ),
                );
              }),
            ),
            // The dock always keeps its space, so the room never changes
            // size; while recording it is hidden under the floating panel.
            IgnorePointer(
              ignoring: recordingUi,
              child: AnimatedOpacity(
                opacity: recordingUi ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: _Dock(
                  onNotes: _openNotes,
                  onRecord: pet.startRecording,
                  noteCount: pet.notes.notes.length,
                ),
              ),
            ),
          ],
        ),
      ),
        // Record panel floats over the bottom of the room (and above the
        // keyboard while you fix the words).
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).viewInsets.bottom,
          child: RecordPanel(pet: pet),
        ),
      ]),
    );
  }
}

/// The two main things: the notes box (with search) and RECORD!.
class _Dock extends StatelessWidget {
  const _Dock({required this.onNotes, required this.onRecord, required this.noteCount});
  final VoidCallback onNotes;
  final VoidCallback onRecord;
  final int noteCount;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, 10 + bottom),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _PotButton(icon: Icons.inventory_2_rounded, label: 'Notes', badge: noteCount > 0 ? '$noteCount' : null, onTap: onNotes),
        const SizedBox(width: 12),
        Expanded(child: _RecordSign(onTap: onRecord)),
      ]),
    );
  }
}

/// Big wooden "RECORD!" sign planted in a pot, like a garden marker.
class _RecordSign extends StatelessWidget {
  const _RecordSign({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Record a voice note',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: DoodleBox(
              seed: 41,
              radius: 14,
              shadow: 5,
              color: Pal.wood,
              padding: const EdgeInsets.all(7),
              child: DoodleBox(
                seed: 43,
                radius: 8,
                color: Pal.cream,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(color: Pal.tomato, shape: BoxShape.circle, border: Border.all(color: ink, width: 2)),
                  ),
                  const SizedBox(width: 8),
                  const Text('RECORD!', style: TextStyle(fontFamily: handFont, fontSize: 30, color: ink, letterSpacing: 1.5, height: 1)),
                ]),
              ),
            ),
          ),
          // two sprouts on top of the sign
          const Positioned(left: 18, top: 0, child: _Sprout()),
          const Positioned(right: 18, top: 0, child: _Sprout(flip: true)),
        ]),
      ),
    );
  }
}

class _Sprout extends StatelessWidget {
  const _Sprout({this.flip = false});
  final bool flip;

  @override
  Widget build(BuildContext context) => Transform.scale(
        scaleX: flip ? -1 : 1,
        child: CustomPaint(size: const Size(28, 20), painter: _SproutPainter()),
      );
}

class _SproutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final l = Path()
      ..moveTo(size.width * 0.45, size.height)
      ..quadraticBezierTo(0, size.height * 0.9, size.width * 0.08, size.height * 0.15)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.3, size.width * 0.45, size.height);
    final r = Path()
      ..moveTo(size.width * 0.5, size.height)
      ..quadraticBezierTo(size.width, size.height * 0.7, size.width * 0.92, 0)
      ..quadraticBezierTo(size.width * 0.45, size.height * 0.2, size.width * 0.5, size.height);
    for (final p in [l, r]) {
      canvas.drawPath(p, fillPaint(Pal.sage));
      canvas.drawPath(p, inkPaint(2));
    }
  }

  @override
  bool shouldRepaint(_SproutPainter old) => false;
}

/// Smaller flower-pot button with an icon and a label.
class _PotButton extends StatelessWidget {
  const _PotButton({required this.icon, required this.label, required this.onTap, this.badge});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badge == null ? label : '$label, $badge',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 74,
          child: Stack(clipBehavior: Clip.none, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              DoodleBox(
                seed: label.length,
                radius: 12,
                shadow: 4,
                color: Pal.woodLight,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: Center(child: Icon(icon, color: ink, size: 30)),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontFamily: handFont, fontSize: 18, color: ink)),
            ]),
            if (badge != null)
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: Pal.tomato, borderRadius: BorderRadius.circular(12), border: Border.all(color: ink, width: 2)),
                  child: Text(badge!, style: const TextStyle(fontFamily: handFont, fontSize: 14, color: Colors.white)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.icon, required this.value, required this.label, required this.seed});
  final String icon;
  final int value;
  final String label;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: DoodleBox(
        seed: seed,
        radius: 6,
        padding: const EdgeInsets.fromLTRB(8, 2, 14, 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text('$value',
              style: const TextStyle(
                  fontFamily: handFont, fontSize: 20, color: ink, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          text.toUpperCase(),
          key: ValueKey(text),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: handFont, fontSize: 21, color: ink, letterSpacing: 0.8, height: 1.1),
        ),
      ),
    );
  }
}

/// Small helper so other screens can show a character preview.
class PetPreview extends StatelessWidget {
  const PetPreview({super.key, required this.character, this.size = 90, this.locked = false});
  final PetCharacter character;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: locked ? 0.35 : 1,
        child: CustomPaint(
          painter: PetPainter(
            character: character,
            foot: Offset(size / 2, size * 0.95),
            height: size * 0.72,
            mood: PetMood.idle,
            held: HeldItem.none,
            facingLeft: false,
            talking: false,
            time: 1,
            level: 0,
          ),
        ),
      ),
    );
  }
}
