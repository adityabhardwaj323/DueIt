import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/utils/app_timezone.dart';
import '../data/tasks_repository.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsyncValue = ref.watch(tasksStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
      ),
      body: tasksAsyncValue.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks yet. Create one!'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              // Overdue logic: if the due date is before the current Indian business time
              bool isOverdue = false;
              if (task.dueDate != null && !task.isCompleted) {
                final dueTz = tz.TZDateTime.from(task.dueDate!, AppTimezone.businessLocation);
                isOverdue = dueTz.isBefore(AppTimezone.businessNow());
              }

              Color priorityColor = Colors.grey;
              if (task.priority == 'high') priorityColor = Colors.red;
              if (task.priority == 'medium') priorityColor = Colors.orange;
              if (task.priority == 'low') priorityColor = Colors.green;

              return ListTile(
                leading: Checkbox(
                  value: task.isCompleted,
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(tasksRepositoryProvider).updateTaskStatus(task.id, val);
                    }
                  },
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: isOverdue ? Colors.red : null,
                        ),
                      ),
                    ),
                    if (task.priority != null) 
                      Icon(Icons.flag, color: priorityColor, size: 16),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task.description != null) Text(task.description!),
                    if (task.dueDate != null) 
                      Text('Due: ', 
                           style: TextStyle(color: isOverdue ? Colors.red : Colors.grey)),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(task: task),
                  ));
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: ')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const TaskDetailScreen(),
          ));
        },
        child: const Icon(Icons.add),
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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController = TextEditingController(text: widget.task?.description ?? '');
    
    if (widget.task?.dueDate != null) {
      // Displaying the time back to the user conceptually.
      // Assuming they want to see it in Indian time as they entered it.
      final dueTz = tz.TZDateTime.from(widget.task!.dueDate!, AppTimezone.businessLocation);
      _dueDate = dueTz; // tz.TZDateTime is a subclass of DateTime
      _dueTime = TimeOfDay.fromDateTime(dueTz);
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
    if (title.isEmpty) return;

    DateTime? finalDueDate;
    if (_dueDate != null) {
      final time = _dueTime ?? const TimeOfDay(hour: 0, minute: 0);
      finalDueDate = AppTimezone.createBusinessEventTime(
        _dueDate!.year, 
        _dueDate!.month, 
        _dueDate!.day, 
        time.hour, 
        time.minute
      );
    }

    final repo = ref.read(tasksRepositoryProvider);
    if (widget.task == null) {
      await repo.createTask(
        title: title,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        dueDate: finalDueDate,
        priority: _priority,
      );
    } else {
      await repo.updateTask(
        widget.task!.id,
        title: title,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        dueDate: finalDueDate,
        priority: _priority,
      );
    }
    
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'New Task' : 'Task Details'),
        actions: [
          if (widget.task != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await ref.read(tasksRepositoryProvider).deleteTask(widget.task!.id);
                if (mounted) Navigator.of(context).pop();
              },
            ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTask,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
               controller: _titleController,
               decoration: const InputDecoration(labelText: 'Task Title'),
            ),
            TextField(
               controller: _descriptionController,
               decoration: const InputDecoration(labelText: 'Description'),
               maxLines: 3,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(_dueDate == null ? 'Set Due Date' : 'Due: '),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime(2100),
                );
                if (date != null) setState(() => _dueDate = date);
              },
            ),
            ListTile(
              title: Text(_dueTime == null ? 'Set Due Time' : 'Time: '),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _dueTime ?? TimeOfDay.now(),
                );
                if (time != null) setState(() => _dueTime = time);
              },
            ),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _priority = val);
              },
            ),
          ],
        ),
      ),
    );
  }
}
