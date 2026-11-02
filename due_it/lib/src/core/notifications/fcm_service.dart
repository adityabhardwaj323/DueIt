import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  // VAPID key is securely provided via Dart environment variables during build.
  // Example: flutter build web --dart-define=FIREBASE_VAPID_KEY=your_key
  static const String webVapidKey = String.fromEnvironment(
    'FIREBASE_VAPID_KEY',
  );

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('dueit_device_id');
    if (deviceId == null) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final uuid = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      deviceId =
          '${uuid.substring(0, 8)}-${uuid.substring(8, 12)}-${uuid.substring(12, 16)}-${uuid.substring(16, 20)}-${uuid.substring(20)}';
      await prefs.setString('dueit_device_id', deviceId);
    }
    return deviceId;
  }

  Future<void> init() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return; // Only sync for authenticated users

    try {
      // 1. Request Permission
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // 2. Get Token
        String? token = await _messaging.getToken(
          vapidKey: kIsWeb && webVapidKey.isNotEmpty ? webVapidKey : null,
        );
        await _syncToken(token);

        // 3. Listen for Token Refresh
        _messaging.onTokenRefresh
            .listen((newToken) {
              _syncToken(newToken);
            })
            .onError((err) {
              debugPrint('Error on token refresh: $err');
            });
      }
    } catch (e) {
      debugPrint('FCM Initialization / Permission error: $e');
    }
  }

  Future<void> _syncToken(String? token) async {
    if (token == null) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      final deviceId = await _getDeviceId();

      // Safest client-side deduplication without knowing if user_id+device_id is a UNIQUE constraint:
      // First, delete any existing registration for this specific device to prevent orphaned rows
      // if the token changed natively during a refresh.
      await _supabase.from('user_fcm_tokens').delete().match({
        'user_id': user.id,
        'device_id': deviceId,
      });

      // Then, upsert the new token. (Assuming fcm_token has a unique constraint per schema design)
      await _supabase.from('user_fcm_tokens').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'device_id': deviceId,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (e) {
      debugPrint('Error syncing FCM token: $e');
    }
  }

  Future<void> removeToken() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final deviceId = await _getDeviceId();
      // Delete using user_id and device_id for safe multi-device targeting
      await _supabase.from('user_fcm_tokens').delete().match({
        'user_id': user.id,
        'device_id': deviceId,
      });

      // Also delete from Firebase backend so it gets a new one next time
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Error removing FCM token on logout: $e');
    }
  }
}

final fcmService = FCMService();
