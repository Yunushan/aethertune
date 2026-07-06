import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../player/player_controller.dart';
import 'home_screen.dart';

class AetherTuneApp extends StatelessWidget {
  const AetherTuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(
          create: (_) => LibraryStore()..load(),
        ),
        ChangeNotifierProvider<PlayerController>(
          create: (_) => PlayerController()..loadPersistedQueue(),
        ),
      ],
      child: MaterialApp(
        title: 'AetherTune',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
