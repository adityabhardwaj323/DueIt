import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:home_widget/home_widget.dart';

class Task {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final String? priority; // low, medium, high
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.dueDate,
    this.priority,
    this.isCompleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      description: json['description'],
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date']).toLocal()
          : null,
      priority: json['priority'],
      isCompleted: json['is_completed'] ?? false,
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class TasksRepository {
  final SupabaseClient _client;

  TasksRepository(this._client);

  Stream<List<Task>> watchTasks() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();
    return _client
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('due_date', ascending: true)
        .map((data) {
          final tasksList = data.map((json) => Task.fromJson(json)).toList();

          // Update Home Widget asynchronously to avoid blocking the stream pipeline
          final pendingCount = tasksList.where((t) => !t.isCompleted).length;
          Future.microtask(() async {
            try {
              await HomeWidget.saveWidgetData<String>('widget_title', 'DueIt Status');
              await HomeWidget.saveWidgetData<String>(
                'widget_subtitle',
                'You have $pendingCount pending tasks.',
              );
              await HomeWidget.updateWidget(androidName: 'DueItWidgetProvider');
            } catch (_) {}
          });

          return tasksList;
        });
  }

  Future<void> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    String? priority,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('tasks').insert({
      'user_id': userId,
      'title': title,
      'description': description,
      'due_date': dueDate?.toUtc().toIso8601String(),
      'priority': priority,
    });
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? priority,
    bool? isCompleted,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (dueDate != null || clearDueDate) {
      updates['due_date'] = dueDate?.toUtc().toIso8601String();
    }
    if (priority != null) updates['priority'] = priority;
    if (isCompleted != null) updates['is_completed'] = isCompleted;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    await _client
        .from('tasks')
        .update(updates)
        .eq('id', id)
        .eq('user_id', userId);
  }

  Future<void> updateTaskStatus(String id, bool isCompleted) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client
        .from('tasks')
        .update({
          'is_completed': isCompleted,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', userId);

    // The database trigger cancels pending and leased reminder events in the
    // same transaction as the task update.
  }

  Future<void> deleteTask(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('tasks').delete().eq('id', id).eq('user_id', userId);
  }
}

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(Supabase.instance.client);
});

final tasksStreamProvider = StreamProvider<List<Task>>((ref) {
  final repo = ref.watch(tasksRepositoryProvider);
  return repo.watchTasks();
});
