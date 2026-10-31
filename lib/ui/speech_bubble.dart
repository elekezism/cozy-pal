import 'package:flutter/material.dart';

import 'doodle.dart';

/// A hand-drawn speech bubble that floats above the pet and stays on screen.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.text,
    required this.anchor,
    required this.below,
    required this.area,
    this.fromUser = false,
    this.onClose,
  });

  final String text;
  final Offset anchor; // top of the pet's head
  final Offset below; // just under the pet's feet, used when there's no room above
  final Size area;
  final bool fromUser;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final maxW = (area.width * 0.8).clamp(160.0, 340.0);
    const margin = 8.0;
    final left = (anchor.dx - maxW / 2).clamp(margin, area.width - maxW - margin);
    final above = anchor.dy > area.height * 0.3;

    return Positioned(
      left: left,
      width: maxW,
      bottom: above ? area.height - anchor.dy : null,
      top: above ? null : below.dy,
      child: Align(
        alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
        child: GestureDetector(
          onTap: onClose,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: ConstrainedBox(
              key: ValueKey(text),
              constraints: BoxConstraints(maxHeight: area.height * 0.4),
              child: DoodleBox(
                seed: text.length,
                radius: 14,
                color: fromUser ? const Color(0xFFE3F2FF) : Pal.cream,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    style: const TextStyle(fontFamily: handFont, color: ink, fontSize: 19, height: 1.2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
