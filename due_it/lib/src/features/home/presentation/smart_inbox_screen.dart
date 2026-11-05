import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/app_timezone.dart';
import '../../expenses/data/dues_repository.dart';
import '../../expenses/data/personal_expenses_repository.dart';
import '../../expenses/presentation/dues_screen.dart';
import '../../expenses/presentation/personal_expenses_screen.dart';
import '../../notes/data/notes_repository.dart';
import '../../notes/presentation/notes_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../tasks/data/tasks_repository.dart';
import '../../tasks/data/streak_tasks_repository.dart';
import '../../tasks/presentation/habits_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';

class SmartInboxScreen extends ConsumerWidget {
  const SmartInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch every dashboard source in the same build. Nesting these watches
    // inside each other's data callbacks serializes first-load subscriptions.
    final notesAsync = ref.watch(notesStreamProvider);
    final tasksAsync = ref.watch(tasksStreamProvider);
    final duesAsync = ref.watch(duesStreamProvider);
    final habitsAsync = ref.watch(streakTasksStreamProvider);
    final expensesAsync = ref.watch(personalExpensesStreamProvider);

    final hasAnyError = notesAsync.hasError &&
        tasksAsync.hasError &&
        duesAsync.hasError &&
        habitsAsync.hasError &&
        expensesAsync.hasError;

    final Widget dashboardBody;
    if (hasAnyError) {
      dashboardBody = _ErrorState(
        message: 'Could not connect to sync service.',
        onRetry: () {
          ref.invalidate(notesStreamProvider);
          ref.invalidate(tasksStreamProvider);
          ref.invalidate(duesStreamProvider);
          ref.invalidate(streakTasksStreamProvider);
          ref.invalidate(personalExpensesStreamProvider);
        },
      );
    } else if (notesAsync.hasValue ||
        tasksAsync.hasValue ||
        duesAsync.hasValue ||
        habitsAsync.hasValue ||
        expensesAsync.hasValue) {
      dashboardBody = _DashboardContent(
        notes: notesAsync.value ?? const [],
        tasks: tasksAsync.value ?? const [],
        dues: duesAsync.value ?? const [],
        habits: habitsAsync.value ?? const [],
        expenses: expensesAsync.value ?? const [],
        onQuickAdd: () => _showQuickAddSheet(context),
      );
    } else {
      dashboardBody = const _LoadingState();
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            const Text('Overview'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: dashboardBody,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuickAddSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Quick Add'),
      ),
    );
  }

  void _showQuickAddSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create something', style: theme.textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(
                'Choose what you want to add.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _QuickAddOption(
                icon: Icons.check_circle_outline_rounded,
                title: 'New task',
                subtitle: 'Set a deadline and priority',
                color: theme.colorScheme.primary,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TaskDetailScreen()),
                  );
                },
              ),
              _QuickAddOption(
                icon: Icons.sticky_note_2_outlined,
                title: 'New note',
                subtitle: 'Capture a thought or reminder',
                color: theme.colorScheme.tertiary,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NoteDetailScreen()),
                  );
                },
              ),
              _QuickAddOption(
                icon: Icons.account_balance_wallet_outlined,
                title: 'New due or loan',
                subtitle: 'Track money lent or borrowed',
                color: const Color(0xFF4F8064),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DueDetailScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final List<Note> notes;
  final List<Task> tasks;
  final List<Due> dues;
  final List<StreakTask> habits;
  final List<PersonalExpense> expenses;
  final VoidCallback onQuickAdd;
  const _DashboardContent({
    required this.notes,
    required this.tasks,
    required this.dues,
    required this.habits,
    required this.expenses,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final today = AppTimezone.businessDate();
    final tomorrow = today.add(const Duration(days: 1));
    final focusTasks = tasks.where((task) {
      if (task.isCompleted || task.dueDate == null) return !task.isCompleted;
      return tz.TZDateTime.from(
        task.dueDate!,
        AppTimezone.businessLocation,
      ).isBefore(tomorrow);
    }).toList()..sort(_compareTasks);
    final done = tasks.where((task) => task.isCompleted).length;
    final todayKey = AppTimezone.todayDateKey();
    final habitsDoneToday = habits.where((habit) =>
      habit.lastCompletedDate != null &&
      '${habit.lastCompletedDate!.year.toString().padLeft(4, '0')}-${habit.lastCompletedDate!.month.toString().padLeft(2, '0')}-${habit.lastCompletedDate!.day.toString().padLeft(2, '0')}' == todayKey
    ).length;
    final now = AppTimezone.businessNow();
    final monthExpenses = expenses.where((expense) =>
      expense.expenseDate.year == now.year && expense.expenseDate.month == now.month
    ).toList()..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    final monthExpenseTotal = monthExpenses.fold<double>(0, (sum, expense) => sum + expense.amount);
    final progress = tasks.isEmpty ? 0.0 : done / tasks.length;
    final dueToday = tasks.where((task) {
      if (task.isCompleted || task.dueDate == null) return false;
      final date = tz.TZDateTime.from(
        task.dueDate!,
        AppTimezone.businessLocation,
      );
      return !date.isBefore(today) && date.isBefore(tomorrow);
    }).length;
    final pendingDues = dues.where((due) => due.status != 'settled').toList();
    final borrowed = pendingDues
        .where((due) => due.direction == 'borrowed')
        .fold<double>(0, (sum, due) => sum + due.amount);
    final lent = pendingDues
        .where((due) => due.direction == 'lent')
        .fold<double>(0, (sum, due) => sum + due.amount);
    final desktop = width >= 880;
    final padding = width < 600
        ? 18.0
        : width < 1000
        ? 28.0
        : 48.0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(padding, 22, padding, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeHeader(
                tasks: tasks.length,
                completed: done,
                progress: progress,
                onQuickAdd: onQuickAdd,
              ),
              const SizedBox(height: 22),
              _MetricStrip(
                openTasks: tasks.length - done,
                dueToday: dueToday,
                pendingDues: pendingDues.length,
                habitsDoneToday: habitsDoneToday,
                habitsTotal: habits.length,
                monthExpenseTotal: monthExpenseTotal,
                borrowed: borrowed,
                lent: lent,
              ),
              const SizedBox(height: 28),
              if (desktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: Column(children: [
                      _TaskPanel(tasks: focusTasks),
                      const SizedBox(height: 16),
                      _HabitsPanel(habits: habits),
                    ])),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          _DuesPanel(dues: pendingDues),
                          const SizedBox(height: 16),
                          _ExpensesPanel(expenses: monthExpenses, total: monthExpenseTotal),
                          const SizedBox(height: 16),
                          _NotesPanel(notes: notes.take(3).toList()),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _TaskPanel(tasks: focusTasks),
                const SizedBox(height: 18),
                _HabitsPanel(habits: habits),
                const SizedBox(height: 18),
                _DuesPanel(dues: pendingDues),
                const SizedBox(height: 18),
                _ExpensesPanel(expenses: monthExpenses, total: monthExpenseTotal),
                const SizedBox(height: 18),
                _NotesPanel(notes: notes.take(3).toList()),
              ],
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  int _compareTasks(Task a, Task b) {
    if (a.dueDate == null) return b.dueDate == null ? 0 : 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  }
}

class _WelcomeHeader extends StatelessWidget {
  final int tasks;
  final int completed;
  final double progress;
  final VoidCallback onQuickAdd;
  const _WelcomeHeader({
    required this.tasks,
    required this.completed,
    required this.progress,
    required this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final date = AppTimezone.businessNow();
    final dateLabel =
        '${_weekday(date.weekday).toUpperCase()}  ·  ${_month(date.month).toUpperCase()} ${date.day}';
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(width < 600 ? 20 : 26),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.primary.withOpacity(0.2)
              : theme.colorScheme.primary.withOpacity(0.12),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  theme.cardColor,
                  theme.colorScheme.primary.withOpacity(0.08),
                ]
              : [
                  theme.cardColor,
                  theme.colorScheme.primary.withOpacity(0.04),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : theme.colorScheme.primary.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    dateLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _greeting(date.hour),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tasks == 0
                      ? 'A little progress is still progress.'
                      : '$completed of $tasks tasks complete. Keep your day moving at your pace.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (width >= 700) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onQuickAdd,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create something'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          _CompletionRing(
            progress: progress,
            completed: completed,
            total: tasks,
          ),
        ],
      ),
    );
  }
}

class _CompletionRing extends StatelessWidget {
  final double progress;
  final int completed;
  final int total;
  const _CompletionRing({
    required this.progress,
    required this.completed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final size = width < 400
        ? 76.0
        : width < 600
        ? 88.0
        : 108.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0, 1),
              strokeWidth: width < 600 ? 7 : 9,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: .10),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              Text(
                total == 0 ? 'No tasks' : '$completed / $total done',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  final int openTasks;
  final int dueToday;
  final int pendingDues;
  final int habitsDoneToday;
  final int habitsTotal;
  final double monthExpenseTotal;
  final double borrowed;
  final double lent;
  const _MetricStrip({
    required this.openTasks,
    required this.dueToday,
    required this.pendingDues,
    required this.habitsDoneToday,
    required this.habitsTotal,
    required this.monthExpenseTotal,
    required this.borrowed,
    required this.lent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final gap = compact ? 9.0 : 14.0;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth < 600 ? 2 : 5;
      final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(width: tileWidth, child: _MetricTile(
            label: 'Open tasks',
            value: '$openTasks',
            icon: Icons.checklist_rounded,
            tint: theme.colorScheme.primary,
            compact: compact,
          )),
          SizedBox(width: tileWidth, child: _MetricTile(
            label: 'Due today',
            value: '$dueToday',
            icon: Icons.today_outlined,
            tint: const Color(0xFFB9784D),
            compact: compact,
          )),
          SizedBox(width: tileWidth, child: _MetricTile(
            label: 'Habits today',
            value: '$habitsDoneToday/$habitsTotal',
            icon: Icons.local_fire_department_outlined,
            tint: const Color(0xFFC27D48),
            compact: compact,
            detail: habitsTotal == 0 ? 'No habits yet' : 'Completed today',
          )),
          SizedBox(width: tileWidth, child: _MetricTile(
            label: 'Expenses this month',
            value: _money(monthExpenseTotal),
            icon: Icons.receipt_long_outlined,
            tint: const Color(0xFF5475A6),
            compact: compact,
            detail: 'Personal expenses',
          )),
          SizedBox(width: tileWidth, child: _MetricTile(
            label: 'Pending dues',
            value: '$pendingDues',
            icon: Icons.account_balance_wallet_outlined,
            tint: const Color(0xFF4F8064),
            compact: compact,
            detail: pendingDues == 0
                ? 'All settled'
                : 'Owe ${_money(borrowed)} · owed ${_money(lent)}',
          )),
        ],
      );
    });
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final bool compact;
  final String? detail;
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.compact,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2E38) : const Color(0xFFE8E8EE),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : tint.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!compact) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint, size: 19),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -.5,
                  ),
                ),
                if (detail != null && !compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPanel extends ConsumerWidget {
  final List<Task> tasks;
  const _TaskPanel({required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            title: 'Today’s workload',
            subtitle: tasks.isEmpty
                ? 'A calm space for what matters'
                : '${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'} to focus on',
            trailing: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TasksScreen()),
              ),
              child: const Text('All tasks'),
            ),
          ),
          if (tasks.isEmpty)
            const _InlineEmpty(
              icon: Icons.task_alt_rounded,
              title: 'Your plate is clear',
              message:
                  'Nothing is due today. Add a task whenever you’re ready.',
            )
          else
            ...tasks.map(
              (task) => _DashboardTaskRow(
                task: task,
                onToggle: (value) => ref
                    .read(tasksRepositoryProvider)
                    .updateTaskStatus(task.id, value),
                onOpen: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(task: task),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardTaskRow extends StatelessWidget {
  final Task task;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;
  const _DashboardTaskRow({
    required this.task,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = task.dueDate == null
        ? null
        : tz.TZDateTime.from(task.dueDate!, AppTimezone.businessLocation);
    final overdue = due != null && due.isBefore(AppTimezone.businessNow());
    final statusColor = overdue
        ? const Color(0xFFB45652)
        : theme.colorScheme.primary;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(
          children: [
            Checkbox(
              value: task.isCompleted,
              onChanged: (value) {
                if (value != null) onToggle(value);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (task.description?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    children: [
                      _StatusPill(
                        label: due == null
                            ? 'No deadline'
                            : overdue
                            ? 'Overdue · ${_time(due)}'
                            : _dueLabel(due),
                        color: statusColor,
                        icon: overdue
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                      ),
                      if (task.priority != null)
                        _PriorityPill(priority: task.priority!),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .65),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitsPanel extends StatelessWidget {
  final List<StreakTask> habits;
  const _HabitsPanel({required this.habits});

  @override
  Widget build(BuildContext context) {
    final todayKey = AppTimezone.todayDateKey();
    final completed = habits.where((habit) {
      final date = habit.lastCompletedDate;
      return date != null &&
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' == todayKey;
    }).length;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            title: 'Habits',
            subtitle: habits.isEmpty ? 'Build a routine, one day at a time' : '$completed of ${habits.length} completed today',
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HabitsScreen())),
              child: const Text('View'),
            ),
          ),
          if (habits.isEmpty)
            const _InlineEmpty(icon: Icons.local_fire_department_outlined, title: 'No habits yet', message: 'Add a habit to start building your routine.')
          else
            ...habits.take(4).map((habit) {
              final date = habit.lastCompletedDate;
              final doneToday = date != null && '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' == todayKey;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: Icon(doneToday ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: doneToday ? const Color(0xFF4F8064) : Theme.of(context).colorScheme.onSurfaceVariant),
                title: Text(habit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('🔥 ${habit.currentStreak} day${habit.currentStreak == 1 ? '' : 's'} · Best ${habit.bestStreak}'),
              );
            }),
        ],
      ),
    );
  }
}

class _ExpensesPanel extends StatelessWidget {
  final List<PersonalExpense> expenses;
  final double total;
  const _ExpensesPanel({required this.expenses, required this.total});

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeading(
          title: 'Personal expenses',
          subtitle: 'This month · ${_money(total)}',
          trailing: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalExpensesScreen())),
            child: const Text('View'),
          ),
        ),
        if (expenses.isEmpty)
          const _InlineEmpty(icon: Icons.receipt_long_outlined, title: 'No expenses this month', message: 'Expenses you record will show here.')
        else
          ...expenses.take(3).map((expense) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(expense.description, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(expense.category?.trim().isNotEmpty == true ? expense.category! : 'General'),
            trailing: Text(_money(expense.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
          )),
      ],
    ),
  );
}

class _DuesPanel extends StatelessWidget {
  final List<Due> dues;
  const _DuesPanel({required this.dues});

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeading(
          title: 'Dues to follow up',
          subtitle: dues.isEmpty ? 'Nothing pending' : '${dues.length} pending',
          trailing: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DuesScreen()),
            ),
            child: const Text('View'),
          ),
        ),
        if (dues.isEmpty)
          const _InlineEmpty(
            icon: Icons.account_balance_wallet_outlined,
            title: 'All caught up',
            message: 'Your open dues will appear here.',
          )
        else
          ...dues.take(4).map((due) => _DueRow(due: due)),
      ],
    ),
  );
}

class _DueRow extends ConsumerWidget {
  final Due due;
  const _DueRow({required this.due});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final borrowed = due.direction == 'borrowed';
    final tint = borrowed ? const Color(0xFFB45652) : const Color(0xFF4F8064);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DueDetailScreen(due: due)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                borrowed ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: tint,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    due.personName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    borrowed ? 'You borrowed' : 'You lent',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '₹${due.amount.toStringAsFixed(0)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
            IconButton(
              tooltip: 'Settle Due',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  ref.read(duesRepositoryProvider).settleDue(due.id),
              icon: Icon(
                Icons.check_circle_outline_rounded,
                size: 19,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesPanel extends StatelessWidget {
  final List<Note> notes;
  const _NotesPanel({required this.notes});

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeading(
          title: 'Recent notes',
          subtitle: notes.isEmpty
              ? 'Your thoughts, in one place'
              : 'A few things you saved',
          trailing: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotesScreen()),
            ),
            child: const Text('View'),
          ),
        ),
        if (notes.isEmpty)
          const _InlineEmpty(
            icon: Icons.sticky_note_2_outlined,
            title: 'No notes yet',
            message: 'Keep a quick thought close by adding a note.',
          )
        else
          ...notes.map((note) => _NoteRow(note: note)),
      ],
    ),
  );
}

class _NoteRow extends StatelessWidget {
  final Note note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.notes_rounded,
                color: theme.colorScheme.tertiary,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title?.trim().isNotEmpty == true
                        ? note.title!.trim()
                        : 'Untitled note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2E38) : const Color(0xFFE8E8EE),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.25)
                : theme.colorScheme.primary.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PanelHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _PanelHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _PriorityPill extends StatelessWidget {
  final String priority;
  const _PriorityPill({required this.priority});

  @override
  Widget build(BuildContext context) {
    final value = priority.toLowerCase();
    final color = switch (value) {
      'high' => const Color(0xFFB45652),
      'medium' => const Color(0xFFB9784D),
      'low' => const Color(0xFF4F8064),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${value[0].toUpperCase()}${value.substring(1)} priority',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuickAddOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _QuickAddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text('Getting your day ready…', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Syncing your tasks, notes and dues.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 38,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'We couldn’t sync this section',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _greeting(int hour) => hour < 12
    ? 'Good morning'
    : hour < 17
    ? 'Good afternoon'
    : 'Good evening';
String _weekday(int day) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][day - 1];
String _month(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
String _time(tz.TZDateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _dueLabel(tz.TZDateTime date) {
  final today = AppTimezone.businessDate();
  final day = tz.TZDateTime(
    AppTimezone.businessLocation,
    date.year,
    date.month,
    date.day,
  );
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today · ${_time(date)}';
  if (diff == 1) return 'Tomorrow · ${_time(date)}';
  return '${_month(date.month).substring(0, 3)} ${date.day} · ${_time(date)}';
}

String _money(double value) => '₹${value.toStringAsFixed(0)}';
