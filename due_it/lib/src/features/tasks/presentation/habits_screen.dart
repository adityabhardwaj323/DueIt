import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/streak_tasks_repository.dart';
import '../../../core/utils/app_timezone.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    final now = AppTimezone.businessNow();
    final nextMidnight = tz.TZDateTime(
      AppTimezone.businessLocation,
      now.year,
      now.month,
      now.day + 1,
    );
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      if (mounted) setState(_scheduleMidnightRefresh);
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  Future<void> _editHabit(BuildContext context, {StreakTask? habit}) async {
    final controller = TextEditingController(text: habit?.title ?? '');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(habit == null ? 'New habit' : 'Edit habit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Habit name'),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    try {
      final repo = ref.read(streakTasksRepositoryProvider);
      if (habit == null) {
        await repo.createStreakTask(title);
      } else {
        await repo.updateStreakTask(habit.id, title);
      }
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Could not save habit: $e');
    }
  }

  Future<void> _deleteHabit(BuildContext context, StreakTask habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text(
          '“${habit.title}” and its streak history will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(streakTasksRepositoryProvider).deleteStreakTask(habit.id);
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Could not delete habit: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(streakTasksStreamProvider);
    final today = AppTimezone.businessDate();
    final todayKey = AppTimezone.todayDateKey();
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editHabit(context),
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
      body: habitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load habits: $error')),
        data: (habits) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _WeeklyHabitAnalyzer(
                startDate: weekStart,
                totalHabits: habits.length,
              ),
            ),
            Expanded(
              child: habits.isEmpty
                  ? const Center(
                      child: Text(
                        'Build a routine, one day at a time.\nAdd your first habit to get started.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: habits.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final habit = habits[index];
                        final doneToday =
                            habit.lastCompletedDate != null &&
                            '${habit.lastCompletedDate!.year.toString().padLeft(4, '0')}-${habit.lastCompletedDate!.month.toString().padLeft(2, '0')}-${habit.lastCompletedDate!.day.toString().padLeft(2, '0')}' ==
                                todayKey;
                        final lastKey = habit.lastCompletedDate == null
                            ? null
                            : '${habit.lastCompletedDate!.year.toString().padLeft(4, '0')}-${habit.lastCompletedDate!.month.toString().padLeft(2, '0')}-${habit.lastCompletedDate!.day.toString().padLeft(2, '0')}';
                        final today = AppTimezone.businessDate();
                        final yesterday = DateTime(
                          today.year,
                          today.month,
                          today.day - 1,
                        );
                        final yesterdayKey =
                            '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
                        final currentStreak =
                            (doneToday || lastKey == yesterdayKey)
                            ? habit.currentStreak
                            : 0;
                        return Card(
                          child: ListTile(
                            leading: Tooltip(
                              message: doneToday
                                  ? 'Mark incomplete today'
                                  : 'Mark complete today',
                              child: Checkbox(
                                value: doneToday,
                                onChanged: (checked) async {
                                  HapticFeedback.mediumImpact();
                                  try {
                                    final repository = ref.read(
                                      streakTasksRepositoryProvider,
                                    );
                                    if (checked == true) {
                                      await repository.completeStreakTask(
                                        habit.id,
                                      );
                                    } else {
                                      await repository.uncompleteStreakTask(
                                        habit.id,
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      _showMessage(
                                        context,
                                        'Could not update habit: $e',
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            title: Text(habit.title),
                            subtitle: Text(
                              '🔥 $currentStreak day${currentStreak == 1 ? '' : 's'}  ·  Best ${habit.bestStreak}',
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Habit options',
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editHabit(context, habit: habit);
                                }
                                if (value == 'delete') {
                                  _deleteHabit(context, habit);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyHabitAnalyzer extends ConsumerWidget {
  final DateTime startDate;
  final int totalHabits;

  const _WeeklyHabitAnalyzer({
    required this.startDate,
    required this.totalHabits,
  });

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayKey = AppTimezone.todayDateKey();
    final endDate = startDate.add(const Duration(days: 6));
    final range = HabitCompletionRange(
      fromDate: _dateKey(startDate),
      throughDate: _dateKey(endDate),
    );
    final completionsAsync = ref.watch(habitCompletionsStreamProvider(range));
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            completionsAsync.when(
              loading: () => const Text('Habit check-ins this week'),
              error: (_, __) => const Text('Habit check-ins this week'),
              data: (completions) => Row(
                children: [
                  Expanded(
                    child: Text(
                      'Habit check-ins this week',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${completions.length} completed',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            completionsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load this week: $error'),
              data: (completions) {
                final days = List.generate(
                  7,
                  (index) => startDate.add(Duration(days: index)),
                );
                final counts = {for (final day in days) _dateKey(day): 0};
                for (final completion in completions) {
                  final key = _dateKey(completion.completedDate);
                  if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
                }
                final weekdayLabels = const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var index = 0; index < days.length; index++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${counts[_dateKey(days[index])]}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 58,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    width: 16,
                                    height: totalHabits == 0
                                        ? 4
                                        : (counts[_dateKey(days[index])]! /
                                                  totalHabits *
                                                  58)
                                              .clamp(4, 58)
                                              .toDouble(),
                                    decoration: BoxDecoration(
                                      color: _dateKey(days[index]) == todayKey
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.primary
                                                .withValues(alpha: 0.32),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                weekdayLabels[index],
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: _dateKey(days[index]) == todayKey
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: _dateKey(days[index]) == todayKey
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${days[index].day}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
