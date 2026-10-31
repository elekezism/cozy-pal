import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/local_ai.dart';
import 'ai/model_manager.dart';
import 'pet_controller.dart';
import 'services/actions_service.dart';
import 'services/cheer_service.dart';
import 'services/email_service.dart';
import 'services/llm_service.dart';
import 'services/memory_service.dart';
import 'services/notes_service.dart';
import 'services/settings_service.dart';
import 'services/voice_service.dart';
import 'ui/room_painter.dart';
import 'ui/room_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = SettingsService();
  await settings.load();
  final notes = NotesService();
  final models = ModelManager();
  await Future.wait([notes.load(), models.init()]);
  final voice = VoiceService(settings);
  await voice.init();
  final localAi = LocalAi(models);
  final email = EmailService(settings);
  final memory = MemoryService(notes: notes, email: email, ai: localAi);
  await memory.load();
  final cheer = CheerService();
  await cheer.load(); // also deletes anything left over from last time
  await cheer.learnFromNotesOnce(notes.notes.map((n) => n.text));

  final pet = PetController(
    settings: settings,
    llm: LlmService(settings),
    email: email,
    notes: notes,
    voice: voice,
    localAi: localAi,
    models: models,
    memory: memory,
    actions: ActionsService(),
    cheer: cheer,
  );

  runApp(CozyPalApp(pet: pet));

  // Load Needle + Whisper in the background if they were downloaded before;
  // the memory index builds itself once Needle is ready. Then refresh mail.
  localAi.loadModels().catchError((Object e) => debugPrint('Model load failed: $e'));
  memory.syncMail().catchError((Object e) => debugPrint('Mail sync failed: $e'));
}

class CozyPalApp extends StatelessWidget {
  const CozyPalApp({super.key, required this.pet});
  final PetController pet;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cozy Pal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: handFont,
        scaffoldBackgroundColor: Pal.sky,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Pal.sage,
          primary: const Color(0xFF4E7A3E),
          surface: Pal.cream,
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        textTheme: ThemeData.light().textTheme.apply(bodyColor: ink, displayColor: ink, fontFamily: handFont),
      ),
      // On a big screen (web), keep the room phone-sized in the middle.
      builder: (context, child) => kIsWeb
          ? ColoredBox(
              color: Pal.sky,
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: child),
              ),
            )
          : child!,
      home: ListenableBuilder(
        listenable: Listenable.merge([pet.settings, pet.notes]),
        builder: (context, _) => RoomScreen(pet: pet),
      ),
    );
  }
}
