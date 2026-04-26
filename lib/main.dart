import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    debugPrint('FCM Token: $token');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a notification: ${message.notification?.title}');
    });
  } catch (e) {
    debugPrint('Notification initialization skipped or failed: $e');
  }

  runApp(const SportGuardApp());
}

class SportGuardApp extends StatelessWidget {
  const SportGuardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportGuard AI',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF35858E),
          primary: const Color(0xFF35858E),
          secondary: const Color(0xFF7DA78C),
          tertiary: const Color(0xFFC2D099),
          surface: const Color(0xFFE6EEC9),
          onSurface: const Color(0xFF1E2A3A),
        ),
        scaffoldBackgroundColor: const Color(0xFFE6EEC9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF35858E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        fontFamily: 'Roboto',
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFFE6EEC9),
              body: Center(child: CircularProgressIndicator(color: Color(0xFF35858E))),
            );
          }

          // If user is logged in, show HomeScreen; otherwise show LoginScreen
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
