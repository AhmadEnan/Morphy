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
        manifestUrl:
            'https://drive.google.com/file/d/1Ld6vwxPk6DZXtiI8IJZ2I5vo0Vv-KYkh/view?usp=sharing',
        assetFolderName: 'asset_test',
        videoOutputFolderName: 'morphy_recordings',
      ),
    );
  }
}
