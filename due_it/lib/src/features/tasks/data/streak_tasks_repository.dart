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
      // This column is a PostgreSQL DATE in the habit's business timezone.
      lastCompletedDate: json['last_completed_date'] == null
          ? null
          : DateTime.parse(
              '${(json['last_completed_date'] as String).split('T').first}T00:00:00',
            ),
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class HabitCompletion {
  final String habitId;
  final DateTime completedDate;

  const HabitCompletion({required this.habitId, required this.completedDate});

  factory HabitCompletion.fromJson(Map<String, dynamic> json) {
    return HabitCompletion(
      habitId: json['habit_id'] as String,
      completedDate: DateTime.parse(json['completed_date'] as String),
    );
  }
}

class HabitCompletionRange {
  final String fromDate;
  final String throughDate;

  const HabitCompletionRange({
    required this.fromDate,
    required this.throughDate,
  });

  @override
  bool operator ==(Object other) =>
      other is HabitCompletionRange &&
      other.fromDate == fromDate &&
      other.throughDate == throughDate;

  @override
  int get hashCode => Object.hash(fromDate, throughDate);
}

class StreakTasksRepository {
  final SupabaseClient _client;

  StreakTasksRepository(this._client);

  Stream<List<StreakTask>> watchStreakTasks() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();
    return _client
        .from('streak_tasks')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((data) => data.map((json) => StreakTask.fromJson(json)).toList());
  }

  Stream<List<HabitCompletion>> watchCompletions({
    required String fromDate,
    required String throughDate,
  }) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();

    return _client
        .from('habit_completions')
        .stream(primaryKey: ['habit_id', 'completed_date'])
        .eq('user_id', userId)
        .gte('completed_date', fromDate)
        .lte('completed_date', throughDate)
        .map(
          (data) => data.map((json) => HabitCompletion.fromJson(json)).toList(),
        );
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
    await _client
        .from('streak_tasks')
        .update({
          'title': title,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> completeStreakTask(String id) async {
    final taskData = await _client
        .from('streak_tasks')
        .select()
        .eq('id', id)
        .single();

    final todayKey = AppTimezone.todayDateKey();
    final String? lastCompletedKey = taskData['last_completed_date']
        ?.toString();
    final alreadyCompletedToday = lastCompletedKey == todayKey;
    final today = AppTimezone.businessDate();
    final yesterday = tz.TZDateTime(
      AppTimezone.businessLocation,
      today.year,
      today.month,
      today.day - 1,
    );
    final isConsecutive =
        lastCompletedKey ==
        '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (!alreadyCompletedToday) {
      final previousCurrentStreak = (taskData['current_streak'] as int?) ?? 0;
      final previousBestStreak = (taskData['best_streak'] as int?) ?? 0;
      int currentStreak = previousCurrentStreak;
      int bestStreak = previousBestStreak;

      if (lastCompletedKey == null) {
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

      await _client
          .from('streak_tasks')
          .update({
            'current_streak': currentStreak,
            'best_streak': bestStreak,
            // A DATE keeps the midnight reset aligned to Asia/Kolkata, independent
            // of the device timezone or the database server timezone.
            'last_completed_date': todayKey,
            'completion_snapshot_date': todayKey,
            'previous_last_completed_date': lastCompletedKey,
            'previous_current_streak': previousCurrentStreak,
            'previous_best_streak': previousBestStreak,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    }

    await _client.from('habit_completions').upsert({
      'habit_id': id,
      'user_id': taskData['user_id'],
      'completed_date': todayKey,
    }, onConflict: 'habit_id,completed_date');
  }

  Future<void> uncompleteStreakTask(String id) async {
    final taskData = await _client
        .from('streak_tasks')
        .select()
        .eq('id', id)
        .single();

    final todayKey = AppTimezone.todayDateKey();
    if (taskData['last_completed_date']?.toString() != todayKey) return;

    final today = AppTimezone.businessDate();
    final yesterday = tz.TZDateTime(
      AppTimezone.businessLocation,
      today.year,
      today.month,
      today.day - 1,
    );
    final yesterdayKey =
        '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final hasTodaySnapshot =
        taskData['completion_snapshot_date']?.toString() == todayKey;
    final previousLastDate = hasTodaySnapshot
        ? taskData['previous_last_completed_date']?.toString()
        : ((taskData['current_streak'] as int? ?? 0) > 1 ? yesterdayKey : null);
    final currentStreak = (taskData['current_streak'] as int?) ?? 0;
    final restoredCurrentStreak = hasTodaySnapshot
        ? (taskData['previous_current_streak'] as int? ?? 0)
        : (currentStreak > 0 ? currentStreak - 1 : 0);
    final restoredBestStreak = hasTodaySnapshot
        ? (taskData['previous_best_streak'] as int? ?? 0)
        : (taskData['best_streak'] as int? ?? 0);

    await _client
        .from('streak_tasks')
        .update({
          'last_completed_date': previousLastDate,
          'current_streak': restoredCurrentStreak,
          'best_streak': restoredBestStreak,
          'completion_snapshot_date': null,
          'previous_last_completed_date': null,
          'previous_current_streak': null,
          'previous_best_streak': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);

    await _client
        .from('habit_completions')
        .delete()
        .eq('habit_id', id)
        .eq('completed_date', todayKey);
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

final habitCompletionsStreamProvider =
    StreamProvider.family<List<HabitCompletion>, HabitCompletionRange>((
      ref,
      range,
    ) {
      final repo = ref.watch(streakTasksRepositoryProvider);
      return repo.watchCompletions(
        fromDate: range.fromDate,
        throughDate: range.throughDate,
      );
    });
