import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'web_export_stub.dart' if (dart.library.html) 'web_export_web.dart';
import '../../../core/notifications/fcm_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _exportData(BuildContext context) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      // Fetch all data
      final notes = await client.from('notes').select();
      final tasks = await client.from('tasks').select();
      final streakTasks = await client.from('streak_tasks').select();
      final dues = await client.from('dues').select();
      final personalExpenses = await client.from('personal_expenses').select();

      final exportData = {
        'export_date': DateTime.now().toIso8601String(),
        'notes': notes,
        'tasks': tasks,
        'streak_tasks': streakTasks,
        'dues': dues,
        'personal_expenses': personalExpenses,
      };

      final jsonString = jsonEncode(exportData);

      if (kIsWeb) {
        // Web download
        downloadWebData(jsonString, "dueit_export_${DateTime.now().millisecondsSinceEpoch}.json");
      } else {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Export Data'),
            content: const Text('JSON export is only fully supported on Web in this MVP iteration. On mobile, we will add share_plus later.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
            ],
          )
        );
      }

      if (context.mounted && kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export downloaded successfully!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export Data (JSON)'),
            subtitle: const Text('Download all your notes, tasks, streaks, and dues'),
            onTap: () => _exportData(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await fcmService.removeToken();
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
