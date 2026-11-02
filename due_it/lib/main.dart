import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:due_it/src/features/auth/presentation/auth_screen.dart';
import 'package:due_it/src/features/home/presentation/main_layout.dart';
import 'package:due_it/src/core/utils/app_timezone.dart';

import 'firebase_options.dart';

import 'package:due_it/src/core/theme/app_theme.dart';
import 'package:due_it/src/core/theme/theme_provider.dart';

const supabaseUrl = 'https://xfgayjbfhmoiqmrvbhje.supabase.co';
const supabaseAnonKey = 'sb_publishable_5ly1RkGDqXdKAFP2dMDrsg_qE3_5ErR';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Business Timezone (Asia/Kolkata)
  await AppTimezone.initialize();

  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUri: true,
    ),
  );

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print(
      'Firebase initialization failed: $e. Make sure google-services.json is configured.',
    );
  }

  runApp(const ProviderScope(child: DueItApp()));
}

class DueItApp extends ConsumerWidget {
  const DueItApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentThemeKey = ref.watch(themeProvider);

    return MaterialApp(
      title: 'DueIt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(currentThemeKey),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _recoveringPassword = false;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _recoveringPassword = true);
      } else if (state.event == AuthChangeEvent.signedOut) {
        setState(() => _recoveringPassword = false);
      } else if (state.session != null) {
        // Rebuild the root when password or OAuth sign-in completes, and keep
        // persisted sessions visible after token refresh events.
        setState(() => _recoveringPassword = false);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recoveringPassword) {
      return PasswordRecoveryScreen(
        onComplete: () {
          setState(() => _recoveringPassword = false);
        },
      );
    }
    return Supabase.instance.client.auth.currentSession == null
        ? const AuthScreen()
        : const MainLayout();
  }
}
