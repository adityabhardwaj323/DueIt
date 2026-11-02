import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/fcm_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<List<Map<String, dynamic>>> _fetchUserRows(
    SupabaseClient client,
    String table,
    String userId,
  ) async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 1000;
    for (var offset = 0; ; offset += pageSize) {
      final baseQuery = client.from(table).select().eq('user_id', userId);
      final orderedQuery = table == 'habit_completions'
          ? baseQuery
                .order('completed_date', ascending: true)
                .order('habit_id', ascending: true)
          : baseQuery
                .order('created_at', ascending: true)
                .order('id', ascending: true);
      final page = await orderedQuery.range(offset, offset + pageSize - 1);
      rows.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < pageSize) return rows;
    }
  }

  Future<void> _exportData(BuildContext context, {required bool csv}) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final tables = <String>[
        'notes',
        'tasks',
        'streak_tasks',
        'habit_completions',
        'dues',
        'personal_expenses',
      ];
      final data = <String, List<Map<String, dynamic>>>{};
      for (final table in tables) {
        data[table] = await _fetchUserRows(client, table, userId);
      }

      final exportData = <String, dynamic>{
        'export_date': DateTime.now().toIso8601String(),
        ...data,
      };
      final filename =
          'dueit_export_${DateTime.now().millisecondsSinceEpoch}.${csv ? 'csv' : 'json'}';
      final mimeType = csv ? 'text/csv' : 'application/json';
      final content = csv
          ? _toCsv(data)
          : const JsonEncoder.withIndent('  ').convert(exportData);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(content), mimeType: mimeType)],
          fileNameOverrides: [filename],
          text: 'DueIt data export',
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export ready to share or save.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  String _toCsv(Map<String, List<Map<String, dynamic>>> data) {
    final rows = <List<String>>[
      ['record_type', 'id', 'created_at', 'data'],
    ];
    for (final entry in data.entries) {
      for (final record in entry.value) {
        rows.add([
          entry.key,
          '${record['id'] ?? ''}',
          '${record['created_at'] ?? ''}',
          jsonEncode(record),
        ]);
      }
    }
    String quote(String value) => '"${value.replaceAll('"', '""')}"';
    return rows.map((row) => row.map(quote).join(',')).join('\r\n');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentThemeKey = ref.watch(themeProvider);
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'User';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Account Profile Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2D2D35)
                      : const Color(0xFFE9E8EE),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primary.withOpacity(
                      0.14,
                    ),
                    child: Text(
                      userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'U',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Signed in as',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          userEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Appearance Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
            child: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Appearance & Themes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),

          // 6 Selectable Themes
          ...AppThemeKey.values.map((themeOption) {
            final isSelected = themeOption == currentThemeKey;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: themeOption.previewColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.black12,
                      width: 1.5,
                    ),
                  ),
                ),
                title: Text(
                  themeOption.displayName,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  themeOption.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : const Icon(
                        Icons.radio_button_off_rounded,
                        color: Colors.grey,
                      ),
                onTap: () {
                  ref.read(themeProvider.notifier).setTheme(themeOption);
                },
              ),
            );
          }),

          // Data Management Section
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
            child: Row(
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Data & Backup',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.download_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              title: const Text(
                'Export Data (JSON)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Download all notes, tasks, and dues records',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _exportData(context, csv: false),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Icon(
                Icons.table_view_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text(
                'Export Data (CSV)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Export records for spreadsheets'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _exportData(context, csv: true),
            ),
          ),

          const SizedBox(height: 16),
          // Logout Option
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text(
                'Log Out',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                await fcmService.removeToken();
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
