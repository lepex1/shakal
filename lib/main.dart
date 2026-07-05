import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'views/main_screen.dart';
import 'windows_accent.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(480, 640));
  await windowManager.setSize(const Size(520, 1130));
  await windowManager.center();
  await windowManager.setTitle('SHAKAL');
  runApp(const ShakalApp());
}

class ShakalApp extends StatefulWidget {
  const ShakalApp({super.key});

  @override
  State<ShakalApp> createState() => _ShakalAppState();
}

class _ShakalAppState extends State<ShakalApp> with WidgetsBindingObserver {
  int _accentColor = 0xFF6750A4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accentColor = getWindowsAccentColor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return MaterialApp(
      title: 'SHAKAL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Color(_accentColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Color(_accentColor),
      ),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const MainScreen(),
    );
  }
}
