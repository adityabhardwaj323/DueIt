import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:due_it/src/features/auth/presentation/auth_screen.dart';
import 'package:due_it/src/features/home/presentation/main_layout.dart';
import 'package:due_it/src/core/utils/app_timezone.dart';
import 'firebase_options.dart';

const supabaseUrl = 'https://xfgayjbfhmoiqmrvbhje.supabase.co';
const supabaseAnonKey = 'sb_publishable_5ly1RkGDqXdKAFP2dMDrsg_qE3_5ErR';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Business Timezone (Asia/Kolkata)
  await AppTimezone.initialize();

  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print('Firebase initialization failed: $e. Make sure google-services.json is configured.');
  }

  runApp(
    const ProviderScope(
      child: DueItApp(),
    ),
  );
}

class DueItApp extends StatelessWidget {
  const DueItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DueIt',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final session = snapshot.data?.session;
          if (session != null) {
            return const MainLayout();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
