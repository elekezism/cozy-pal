import 'package:flutter/material.dart';

import '../models/character.dart';
import '../pet_controller.dart';
import 'room_painter.dart';
import 'room_screen.dart';

Future<void> showWardrobeSheet(BuildContext context, PetController pet) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFFFFF7E6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) => ListenableBuilder(
      listenable: pet.settings,
      builder: (context, _) {
        final treats = pet.settings.treats;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Friends', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 4),
              Text('Earn a 🐟 every time your pet helps you. You have $treats.',
                  textAlign: TextAlign.center, style: const TextStyle(color: ink)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final c in PetCharacter.all)
                    _FriendTile(
                      character: c,
                      selected: c.id == pet.settings.characterId,
                      locked: !c.unlocked(treats),
                      onTap: () {
                        if (!c.unlocked(treats)) return;
                        pet.settings.characterId = c.id;
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ]),
          ),
        );
      },
    ),
  );
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.character, required this.selected, required this.locked, required this.onTap});
  final PetCharacter character;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDDEFD9) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink, width: selected ? 2.4 : 1.4),
        ),
        child: Column(children: [
          PetPreview(character: character, size: 76, locked: locked),
          const SizedBox(height: 4),
          Text(character.name.split(' ').first,
              style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
          Text(
            locked ? '🔒 ${character.treatsToUnlock} 🐟' : (selected ? 'With you' : 'Tap to swap'),
            style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.65)),
          ),
        ]),
      ),
    );
  }
}
