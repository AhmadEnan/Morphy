import 'package:flutter/material.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/startup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- CONFIGURATION ---
  // Configuration moved to StartupScreen
  // ---------------------

  AppTheme.configureSystemUI();
  runApp(const MorphyApp());
}

class MorphyApp extends StatelessWidget {
  const MorphyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morphy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const StartupScreen(
        // Direct folder URL - syncs the effects folder structure from GitHub
        manifestUrl:
            'https://github.com/AhmadEnan/Morphy/tree/main/assets/effects/',
        assetFolderName: 'morphy_assets',
        videoOutputFolderName: 'morphy_recordings',
      ),
    );
  }
}
