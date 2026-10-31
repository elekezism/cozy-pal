import 'package:flutter/painting.dart';

enum EarStyle { pointy, floppy, long, round }

enum TailStyle { curl, fluffy, puff, none }

/// A pet friend. The cat is free; the others unlock with fish treats,
/// which the pet earns every time it helps.
class PetCharacter {
  const PetCharacter({
    required this.id,
    required this.name,
    required this.body,
    required this.belly,
    required this.ears,
    required this.tail,
    required this.treatsToUnlock,
    this.innerEar = const Color(0xFFF4B6B0),
    this.patch,
    this.accessory = const Color(0xFFE2725B),
    this.spiky = false,
  });

  final String id;
  final String name;
  final Color body;
  final Color belly;
  final Color innerEar;
  final Color? patch;
  final Color accessory;
  final EarStyle ears;
  final TailStyle tail;
  final int treatsToUnlock;
  final bool spiky;

  bool unlocked(int treats) => treats >= treatsToUnlock;

  static const all = <PetCharacter>[
    PetCharacter(
      id: 'cat',
      name: 'Mochi the Cat',
      body: Color(0xFFF4B26E),
      belly: Color(0xFFFDE7C8),
      patch: Color(0xFFD98A45),
      ears: EarStyle.pointy,
      tail: TailStyle.curl,
      treatsToUnlock: 0,
    ),
    PetCharacter(
      id: 'bunny',
      name: 'Pip the Bunny',
      body: Color(0xFFF6F0E8),
      belly: Color(0xFFFFFFFF),
      ears: EarStyle.long,
      tail: TailStyle.puff,
      accessory: Color(0xFF8FC0DE),
      treatsToUnlock: 10,
    ),
    PetCharacter(
      id: 'pup',
      name: 'Biscuit the Pup',
      body: Color(0xFFE0A665),
      belly: Color(0xFFF7DFBB),
      patch: Color(0xFFB87A3F),
      ears: EarStyle.floppy,
      tail: TailStyle.fluffy,
      accessory: Color(0xFFE2725B),
      treatsToUnlock: 25,
    ),
    PetCharacter(
      id: 'hamster',
      name: 'Nugget the Hamster',
      body: Color(0xFFEBB880),
      belly: Color(0xFFFFF3E0),
      ears: EarStyle.round,
      tail: TailStyle.none,
      accessory: Color(0xFFB5D37F),
      treatsToUnlock: 40,
    ),
    PetCharacter(
      id: 'hedgehog',
      name: 'Bramble the Hedgehog',
      body: Color(0xFFA2724C),
      belly: Color(0xFFF2DCB8),
      ears: EarStyle.round,
      tail: TailStyle.none,
      accessory: Color(0xFFF2C14E),
      spiky: true,
      treatsToUnlock: 60,
    ),
  ];

  static PetCharacter byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.first);
}
