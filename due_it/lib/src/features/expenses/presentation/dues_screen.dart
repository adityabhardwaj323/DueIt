import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/utils/app_timezone.dart';
import '../data/dues_repository.dart';

class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duesAsyncValue = ref.watch(duesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dues'),
      ),
      body: duesAsyncValue.when(
        data: (dues) {
          if (dues.isEmpty) {
            return const Center(child: Text('No dues. You are all settled!'));
          }
          return ListView.builder(
            itemCount: dues.length,
            itemBuilder: (context, index) {
              final due = dues[index];
              final isSettled = due.status == 'settled';
              
              bool isOverdue = due.status == 'overdue';
              if (!isSettled && due.dueDate != null) {
                final dueTz = tz.TZDateTime.from(due.dueDate!, AppTimezone.businessLocation);
                if (dueTz.isBefore(AppTimezone.businessNow())) {
                  isOverdue = true;
                }
              }

              final isBorrowed = due.direction == 'borrowed';

              return ListTile(
                leading: Icon(
                  isBorrowed ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isSettled ? Colors.grey : (isBorrowed ? Colors.red : Colors.green),
                ),
                title: Text(
                  '\{due.amount.toStringAsFixed(2)} - ${due.personName}',
                  style: TextStyle(
                    decoration: isSettled ? TextDecoration.lineThrough : null,
                    color: isOverdue && !isSettled ? Colors.red : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (due.reason != null && due.reason!.isNotEmpty) 
                      Text(due.reason!),
                    if (due.dueDate != null) 
                      Text('Due: ', 
                           style: TextStyle(color: isOverdue && !isSettled ? Colors.red : Colors.grey)),
                  ],
                ),
                trailing: isSettled 
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : IconButton(
                        icon: const Icon(Icons.payment),
                        onPressed: () {
                          ref.read(duesRepositoryProvider).settleDue(due.id);
                        },
                      ),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DueDetailScreen(due: due),
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
            builder: (_) => const DueDetailScreen(),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class DueDetailScreen extends ConsumerStatefulWidget {
  final Due? due;

  const DueDetailScreen({super.key, this.due});

  @override
  ConsumerState<DueDetailScreen> createState() => _DueDetailScreenState();
}

class _DueDetailScreenState extends ConsumerState<DueDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _personName;
  late double _amount;
  late String _direction;
  String? _reason;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _personName = widget.due?.personName ?? '';
    _amount = widget.due?.amount ?? 0.0;
    _direction = widget.due?.direction ?? 'lent';
    _reason = widget.due?.reason;
    
    if (widget.due?.dueDate != null) {
      _dueDate = tz.TZDateTime.from(widget.due!.dueDate!, AppTimezone.businessLocation);
    }
  }

  Future<void> _saveDue() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    DateTime? finalDueDate;
    if (_dueDate != null) {
      finalDueDate = AppTimezone.createBusinessEventTime(
        _dueDate!.year, 
        _dueDate!.month, 
        _dueDate!.day, 
        23, 
        59
      );
    }

    final repo = ref.read(duesRepositoryProvider);
    if (widget.due == null) {
      await repo.createDue(
        personName: _personName,
        amount: _amount,
        direction: _direction,
        reason: _reason,
        dueDate: finalDueDate,
        transactionDate: DateTime.now().toUtc(),
      );
    } else {
      await repo.updateDue(
        widget.due!.id,
        personName: _personName,
        amount: _amount,
        direction: _direction,
        reason: _reason,
        dueDate: finalDueDate,
      );
    }
    
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.due == null ? 'New Due' : 'Edit Due'),
        actions: [
          if (widget.due != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await ref.read(duesRepositoryProvider).deleteDue(widget.due!.id);
                if (mounted) Navigator.of(context).pop();
              },
            ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveDue,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _direction,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'lent', child: Text('I lent someone money')),
                  DropdownMenuItem(value: 'borrowed', child: Text('I borrowed money')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _direction = val);
                },
              ),
              TextFormField(
                initialValue: _personName,
                decoration: const InputDecoration(labelText: 'Person Name'),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                onSaved: (val) => _personName = val!,
              ),
              TextFormField(
                initialValue: widget.due == null ? '' : _amount.toString(),
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  if (double.tryParse(val) == null) return 'Invalid amount';
                  return null;
                },
                onSaved: (val) => _amount = double.parse(val!),
              ),
              TextFormField(
                initialValue: _reason,
                decoration: const InputDecoration(labelText: 'Reason (Optional)'),
                onSaved: (val) => _reason = val,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(_dueDate == null ? 'Set Due Date' : 'Due: '),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final nowTz = AppTimezone.businessNow();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? nowTz,
                    firstDate: nowTz.subtract(const Duration(days: 1)),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) setState(() => _dueDate = date);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
