import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/utils/app_timezone.dart';

class StreakTask {
  final String id;
  final String userId;
  final String title;
  final int currentStreak;
  final int bestStreak;
  final DateTime? lastCompletedDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  StreakTask({
    required this.id,
    required this.userId,
    required this.title,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastCompletedDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StreakTask.fromJson(Map<String, dynamic> json) {
    return StreakTask(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      currentStreak: json['current_streak'] ?? 0,
      bestStreak: json['best_streak'] ?? 0,
      lastCompletedDate: json['last_completed_date'] != null ? DateTime.parse(json['last_completed_date']).toLocal() : null,
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class StreakTasksRepository {
  final SupabaseClient _client;

  StreakTasksRepository(this._client);

  Stream<List<StreakTask>> watchStreakTasks() {
    return _client
        .from('streak_tasks')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map((json) => StreakTask.fromJson(json)).toList());
  }

  Future<void> createStreakTask(String title) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('streak_tasks').insert({
      'user_id': userId,
      'title': title,
    });
  }

  Future<void> updateStreakTask(String id, String title) async {
    await _client.from('streak_tasks').update({
      'title': title,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> completeStreakTask(String id) async {
    final taskData = await _client.from('streak_tasks').select().eq('id', id).single();
    
    final String? lastCompletedStr = taskData['last_completed_date'];
    
    final todayKey = AppTimezone.todayDateKey();
    
    bool alreadyCompletedToday = false;
    bool isConsecutive = false;

    if (lastCompletedStr != null) {
      final lastCompleted = DateTime.parse(lastCompletedStr);
      final lastKey = AppTimezone.dateKey(lastCompleted);
      
      alreadyCompletedToday = (todayKey == lastKey);
      
      if (!alreadyCompletedToday) {
        final lastTz = tz.TZDateTime.from(lastCompleted, AppTimezone.businessLocation);
        final lastDate = tz.TZDateTime(AppTimezone.businessLocation, lastTz.year, lastTz.month, lastTz.day);
        final todayDate = AppTimezone.businessDate();
        
        // Check if exactly 1 calendar day apart
        isConsecutive = (todayDate.difference(lastDate).inDays == 1);
      }
    }

    if (!alreadyCompletedToday) {
      int currentStreak = (taskData['current_streak'] as int?) ?? 0;
      int bestStreak = (taskData['best_streak'] as int?) ?? 0;
      
      if (lastCompletedStr == null) {
        // First completion ever
        currentStreak = 1;
      } else if (isConsecutive) {
        // Streak continues
        currentStreak++;
      } else {
        // Streak broken
        currentStreak = 1;
      }

      if (currentStreak > bestStreak) {
        bestStreak = currentStreak;
      }
      
      // Store absolute UTC timestamp safely
      final nowUtc = DateTime.now().toUtc();
      
      await _client.from('streak_tasks').update({
        'current_streak': currentStreak,
        'best_streak': bestStreak,
        'last_completed_date': nowUtc.toIso8601String(),
        'updated_at': nowUtc.toIso8601String(),
      }).eq('id', id);
    }
  }

  Future<void> deleteStreakTask(String id) async {
    await _client.from('streak_tasks').delete().eq('id', id);
  }
}

final streakTasksRepositoryProvider = Provider<StreakTasksRepository>((ref) {
  return StreakTasksRepository(Supabase.instance.client);
});

final streakTasksStreamProvider = StreamProvider<List<StreakTask>>((ref) {
  final repo = ref.watch(streakTasksRepositoryProvider);
  return repo.watchStreakTasks();
});
