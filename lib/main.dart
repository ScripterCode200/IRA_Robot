import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/dashboard_screen.dart';
import 'screens/control_screen.dart';
import 'screens/face_screen.dart';

import 'services/memory_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Limit image cache to prevent memory bloat from video frames
  PaintingBinding.instance.imageCache.maximumSize = 20;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024; // 20MB

  await MemoryService.initialize();
  
  // Set orientation to support both portrait and landscape (Cockpit controls adapt gracefully)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // High-tech translucent system overlay styling
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF070A13),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const RobotCompanionApp());
}

class RobotCompanionApp extends StatelessWidget {
  const RobotCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32-S3 Robot Cockpit',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE),      // Neon Teal
          secondary: Color(0xFF8B5CF6),    // Laser Violet
          background: Color(0xFF0B0F19),
          surface: Color(0xFF1E293B),
          onPrimary: Colors.black,
          onSecondary: Colors.white,
        ),
        fontFamily: 'monospace', // Gives a beautiful technical system interface aesthetic
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF070A13),
          selectedItemColor: Color(0xFF00F2FE),
          unselectedItemColor: Colors.blueGrey,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
          unselectedLabelStyle: TextStyle(fontSize: 9, letterSpacing: 1),
        ),
      ),
      home: const MainCockpitShell(),
    );
  }
}

class MainCockpitShell extends StatefulWidget {
  const MainCockpitShell({super.key});

  @override
  State<MainCockpitShell> createState() => _MainCockpitShellState();
}

class _MainCockpitShellState extends State<MainCockpitShell> {
  int _currentIndex = 0;
  bool _isConnected = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = _isConnected ? const Color(0xFF00F2FE) : const Color(0xFFD946EF);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(
            isConnected: _isConnected,
            isVisible: _currentIndex == 0,
            onConnectionChanged: (connected) {
              setState(() {
                _isConnected = connected;
              });
            },
          ),
          ControlScreen(
            isConnected: _isConnected,
            isVisible: _currentIndex == 1,
          ),
          FaceScreen(
            isConnected: _isConnected,
            isVisible: _currentIndex == 2,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: activeColor.withOpacity(0.15),
              width: 1.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: activeColor.withOpacity(0.04),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF070A13),
          elevation: 8,
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_customize_rounded, size: 20),
              activeIcon: _buildGlowingIcon(Icons.dashboard_customize_rounded, activeColor),
              label: 'DASHBOARD',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.gamepad_rounded, size: 20),
              activeIcon: _buildGlowingIcon(Icons.gamepad_rounded, const Color(0xFFEC4899)),
              label: 'STEERING',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.face_retouching_natural_rounded, size: 20),
              activeIcon: _buildGlowingIcon(Icons.face_retouching_natural_rounded, const Color(0xFF8B5CF6)),
              label: 'EXPRESSION',
            ),
          ],
          onTap: (index) {
            HapticFeedback.selectionClick();
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildGlowingIcon(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
