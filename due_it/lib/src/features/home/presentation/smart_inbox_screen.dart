import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/utils/app_timezone.dart';

import '../../notes/data/notes_repository.dart';
import '../../tasks/data/tasks_repository.dart';
import '../../expenses/data/dues_repository.dart';

import '../../notes/presentation/notes_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';

class SmartInboxScreen extends ConsumerWidget {
  const SmartInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesStreamProvider);
    final tasksAsync = ref.watch(tasksStreamProvider);
    final duesAsync = ref.watch(duesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Inbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading notes: ')),
        data: (notes) {
          return tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error loading tasks: ')),
            data: (tasks) {
              return duesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error loading dues: ')),
                data: (dues) {
                  // Business Date (Asia/Kolkata)
                  final todayTz = AppTimezone.businessDate();
                  
                  final urgentTasks = tasks.where((t) {
                    if (t.isCompleted) return false;
                    if (t.dueDate != null) {
                      final dueTz = tz.TZDateTime.from(t.dueDate!, AppTimezone.businessLocation);
                      return dueTz.isBefore(todayTz.add(const Duration(days: 1)));
                    }
                    return false;
                  }).toList();

                  final pendingPayments = dues.where((e) => e.status != 'settled').toList();
                  
                  final recentNotes = notes.take(3).toList();

                  final feedItems = <Widget>[];

                  if (urgentTasks.isNotEmpty) {
                    feedItems.add(const _SectionHeader(title: 'Urgent Tasks'));
                    for (var task in urgentTasks) {
                      final isOverdue = task.dueDate != null && tz.TZDateTime.from(task.dueDate!, AppTimezone.businessLocation).isBefore(todayTz);
                      feedItems.add(ListTile(
                        leading: const Icon(Icons.warning, color: Colors.red),
                        title: Text(task.title, style: TextStyle(color: isOverdue ? Colors.red : null)),
                        subtitle: task.dueDate != null ? Text('Due: ') : null,
                        trailing: Checkbox(
                          value: false,
                          onChanged: (_) {
                            ref.read(tasksRepositoryProvider).updateTaskStatus(task.id, true);
                          },
                        ),
                      ));
                    }
                  }

                  if (pendingPayments.isNotEmpty) {
                    feedItems.add(const _SectionHeader(title: 'Pending Dues'));
                    for (var due in pendingPayments) {
                      final isBorrowed = due.direction == 'borrowed';
                      feedItems.add(ListTile(
                        leading: Icon(
                          isBorrowed ? Icons.arrow_downward : Icons.arrow_upward, 
                          color: isBorrowed ? Colors.red : Colors.green
                        ),
                        title: Text(' \{due.amount.toStringAsFixed(2)} - '),
                        subtitle: due.dueDate != null ? Text('Due: ') : null,
                      ));
                    }
                  }

                  if (recentNotes.isNotEmpty) {
                    feedItems.add(const _SectionHeader(title: 'Recent Notes'));
                    for (var note in recentNotes) {
                      feedItems.add(ListTile(
                        leading: const Icon(Icons.note, color: Colors.blue),
                        title: Text(note.title ?? 'Untitled'),
                        subtitle: Text(note.content, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ));
                    }
                  }

                  if (feedItems.isEmpty) {
                    return const Center(
                      child: Text(
                        'You\'re all caught up!\nEnjoy your day.', 
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    );
                  }

                  return ListView(
                    children: feedItems,
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showQuickAddSheet(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showQuickAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.note),
                title: const Text('Quick Note'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NoteDetailScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_box),
                title: const Text('Quick Task'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailScreen()));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}
