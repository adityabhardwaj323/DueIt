import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/app_timezone.dart';
import '../data/tasks_repository.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  String _formatTaskDate(DateTime dt) {
    final businessDt = tz.TZDateTime.from(dt, AppTimezone.businessLocation);
    final today = AppTimezone.businessDate();
    final itemDate = tz.TZDateTime(
      AppTimezone.businessLocation,
      businessDt.year,
      businessDt.month,
      businessDt.day,
    );

    final diffDays = itemDate.difference(today).inDays;
    final timeStr =
        '${businessDt.hour.toString().padLeft(2, '0')}:${businessDt.minute.toString().padLeft(2, '0')}';

    if (diffDays == 0) return 'Today at $timeStr';
    if (diffDays == 1) return 'Tomorrow at $timeStr';
    if (diffDays == -1) return 'Yesterday at $timeStr';
    if (diffDays < -1) return '${-diffDays}d overdue · $timeStr';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[businessDt.month - 1]} ${businessDt.day} · $timeStr';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tasksAsyncValue = ref.watch(tasksStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Tasks'),
          ],
        ),
      ),
      body: tasksAsyncValue.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.task_alt_rounded,
                        size: 54,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No tasks yet',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Organize your day with tasks, deadlines, and priorities.\nTap + to add your first task.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
          final today = AppTimezone.businessDate();
          final tasksByDay = <DateTime, List<Task>>{};
          for (final task in pendingTasks) {
            final due = task.dueDate == null
                ? today
                : tz.TZDateTime.from(
                    task.dueDate!,
                    AppTimezone.businessLocation,
                  );
            final day = DateTime(due.year, due.month, due.day);
            (tasksByDay[day] ??= []).add(task);
          }
          final taskDays = tasksByDay.keys.toList()..sort();
          final completedTasks = tasks.where((t) => t.isCompleted).toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 84),
            children: [
              _buildWeeklyCompletionCard(context, completedTasks),
              ...taskDays.map(
                (day) => _buildTaskDayRow(
                  context,
                  ref,
                  day,
                  tasksByDay[day]!,
                  today,
                  isDark,
                  theme,
                ),
              ),

              if (taskDays.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Text(
                    'You’re all clear. Add a task for today or schedule one for later.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],

              // Completed section
              if (completedTasks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 6),
                  child: Row(
                    children: [
                      Text(
                        'Completed',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${completedTasks.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...completedTasks.map(
                  (task) => _buildTaskCard(context, ref, task, isDark, theme),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Error loading tasks: $error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TaskDetailScreen()));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Task'),
      ),
    );
  }

  Widget _buildCountBadge(BuildContext context, int count, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

  Widget _buildTaskDayRow(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<Task> tasks,
    tz.TZDateTime today,
    bool isDark,
    ThemeData theme,
  ) {
    final difference = DateTime(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final label = difference == 0
        ? 'Today'
        : difference == 1
        ? 'Tomorrow'
        : '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1]}, ${day.day}/${day.month}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Row(
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              _buildCountBadge(
                context,
                tasks.length,
                theme.colorScheme.primary,
              ),
              const Spacer(),
              Icon(
                Icons.swipe_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 144,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => SizedBox(
              width: 320,
              child: _buildTaskCard(context, ref, tasks[index], isDark, theme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyCompletionCard(BuildContext context, List<Task> tasks) {
    final theme = Theme.of(context);
    final now = AppTimezone.businessDate();
    final days = List.generate(
      7,
      (index) => now.subtract(Duration(days: 6 - index)),
    );
    final counts = List.generate(days.length, (index) {
      final day = days[index];
      return tasks.where((task) {
        final completedAt = tz.TZDateTime.from(
          task.updatedAt,
          AppTimezone.businessLocation,
        );
        return completedAt.year == day.year &&
            completedAt.month == day.month &&
            completedAt.day == day.day;
      }).length;
    });
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    final peak = counts.fold<int>(
      0,
      (value, count) => count > value ? count : value,
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'This week',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$total completed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(days.length, (index) {
                  final count = counts[index];
                  final barHeight = peak == 0 ? 4.0 : 6 + 32 * count / peak;
                  final labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                  final isToday = index == days.length - 1;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 5),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: barHeight,
                          width: 16,
                          decoration: BoxDecoration(
                            color: isToday
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.28,
                                  ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[days[index].weekday - 1],
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: isToday ? FontWeight.w700 : null,
                            color: isToday
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    WidgetRef ref,
    Task task,
    bool isDark,
    ThemeData theme,
  ) {
    bool isOverdue = false;
    if (task.dueDate != null && !task.isCompleted) {
      final dueTz = tz.TZDateTime.from(
        task.dueDate!,
        AppTimezone.businessLocation,
      );
      isOverdue = dueTz.isBefore(AppTimezone.businessNow());
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: task.isCompleted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                activeColor: theme.colorScheme.primary,
                onChanged: (val) {
                  if (val != null) {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(tasksRepositoryProvider)
                        .updateTaskStatus(task.id, val);
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isCompleted
                            ? (isDark
                                  ? const Color(0xFF6B7280)
                                  : const Color(0xFF9CA3AF))
                            : (isOverdue ? Colors.redAccent : null),
                      ),
                    ),
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        task.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                    if (task.dueDate != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: isOverdue
                                ? Colors.redAccent
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _formatTaskDate(task.dueDate!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isOverdue
                                    ? Colors.redAccent
                                    : (isDark
                                          ? const Color(0xFF9CA3AF)
                                          : const Color(0xFF6B7280)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (task.priority != null) ...[
                const SizedBox(width: 8),
                _TaskPriorityBadge(priority: task.priority!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskPriorityBadge extends StatelessWidget {
  final String priority;

  const _TaskPriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;
    if (priority == 'high') color = Colors.redAccent;
    if (priority == 'medium') color = Colors.orange;
    if (priority == 'low') color = Colors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class TaskDetailScreen extends ConsumerStatefulWidget {
  final Task? task;

  const TaskDetailScreen({super.key, this.task});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _priority = 'medium';
  String _schedulePreset = 'none';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.task?.description ?? '',
    );

    if (widget.task?.dueDate != null) {
      final dueTz = tz.TZDateTime.from(
        widget.task!.dueDate!,
        AppTimezone.businessLocation,
      );
      _dueDate = dueTz;
      _dueTime = TimeOfDay.fromDateTime(dueTz);
      _schedulePreset = 'custom';
    }

    _priority = widget.task?.priority ?? 'medium';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task title')),
      );
      return;
    }

    setState(() => _isSaving = true);

    DateTime? finalDueDate;
    if (_dueDate != null) {
      final time = _dueTime ?? const TimeOfDay(hour: 12, minute: 0);
      finalDueDate = AppTimezone.createBusinessEventTime(
        _dueDate!.year,
        _dueDate!.month,
        _dueDate!.day,
        time.hour,
        time.minute,
      );
    }

    final repo = ref.read(tasksRepositoryProvider);
    final desc = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    try {
      if (widget.task == null) {
        await repo.createTask(
          title: title,
          description: desc,
          dueDate: finalDueDate,
          priority: _priority,
        );
      } else {
        await repo.updateTask(
          widget.task!.id,
          title: title,
          description: desc,
          dueDate: finalDueDate,
          clearDueDate: finalDueDate == null,
          priority: _priority,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(tasksRepositoryProvider).deleteTask(widget.task!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  DateTime _addCalendarMonth(DateTime date) {
    final month = date.month == 12 ? 1 : date.month + 1;
    final year = date.year + (date.month == 12 ? 1 : 0);
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      date.day.clamp(1, lastDay),
      date.hour,
      date.minute,
    );
  }

  void _applySchedulePreset(String preset) {
    setState(() {
      _schedulePreset = preset;
      if (preset == 'none') {
        _dueDate = null;
        _dueTime = null;
        return;
      }

      final now = AppTimezone.businessNow();
      final scheduled = switch (preset) {
        'today' => tz.TZDateTime(
          AppTimezone.businessLocation,
          now.year,
          now.month,
          now.day,
          23,
          59,
        ),
        '8_hours' => now.add(const Duration(hours: 8)),
        '3_days' => now.add(const Duration(days: 3)),
        '1_week' => now.add(const Duration(days: 7)),
        '1_month' => _addCalendarMonth(now),
        _ => now,
      };
      _dueDate = scheduled;
      _dueTime = TimeOfDay.fromDateTime(scheduled);
    });
  }

  Future<void> _pickCustomDate() async {
    final now = AppTimezone.businessNow();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? TimeOfDay.fromDateTime(now),
    );
    if (!mounted) return;

    setState(() {
      _schedulePreset = 'custom';
      _dueDate = date;
      if (time != null) _dueTime = time;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'New Task' : 'Edit Task'),
        actions: [
          if (widget.task != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.check_rounded),
                    tooltip: 'Save',
                    onPressed: _saveTask,
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                prefixIcon: Icon(Icons.notes_rounded),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule task',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a quick time or set your own date and hour.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        _scheduleChip('No date', 'none'),
                        _scheduleChip('Today', 'today'),
                        _scheduleChip('In 8 hours', '8_hours'),
                        _scheduleChip('In 3 days', '3_days'),
                        _scheduleChip('In 1 week', '1_week'),
                        _scheduleChip('In 1 month', '1_month'),
                        ChoiceChip(
                          label: const Text('Pick date & time'),
                          selected: _schedulePreset == 'custom',
                          onSelected: (_) => _pickCustomDate(),
                        ),
                      ],
                    ),
                    if (_dueDate != null) ...[
                      const Divider(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.calendar_month_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          'Due date: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: _pickCustomDate,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.access_time_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          'Time: ${_dueTime?.format(context) ?? 'Set due time'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: const Icon(Icons.schedule_rounded),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime:
                                _dueTime ??
                                TimeOfDay.fromDateTime(
                                  AppTimezone.businessNow(),
                                ),
                          );
                          if (time != null) setState(() => _dueTime = time);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority Level',
                prefixIcon: Icon(Icons.flag_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low Priority')),
                DropdownMenuItem(
                  value: 'medium',
                  child: Text('Medium Priority'),
                ),
                DropdownMenuItem(value: 'high', child: Text('High Priority')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _priority = val);
              },
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveTask,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.task == null ? 'Create Task' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleChip(String label, String value) => ChoiceChip(
    label: Text(label),
    selected: _schedulePreset == value,
    onSelected: (_) => _applySchedulePreset(value),
  );
}
