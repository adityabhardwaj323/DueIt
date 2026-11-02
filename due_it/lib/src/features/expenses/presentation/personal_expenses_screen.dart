import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:due_it/src/features/expenses/data/dues_repository.dart';

import '../data/personal_expenses_repository.dart';
import 'dues_screen.dart';

class PersonalExpensesScreen extends ConsumerStatefulWidget {
  const PersonalExpensesScreen({super.key});

  @override
  ConsumerState<PersonalExpensesScreen> createState() =>
      _PersonalExpensesScreenState();
}

class _PersonalExpensesScreenState
    extends ConsumerState<PersonalExpensesScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
      );
    });
  }

  String _monthLabel(DateTime date) {
    const months = [
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
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Future<void> _deletePersonalExpense(PersonalExpense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('“${expense.description}” will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(personalExpensesRepositoryProvider)
          .deleteExpense(expense.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete expense: $error')),
        );
      }
    }
  }

  Future<void> _deleteDueEntry(Due due) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this person entry?'),
        content: Text(
          'This removes ${due.personName}’s ${due.direction == 'lent' ? 'amount owed to you' : 'amount you owe'} entry from the expense total and account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete entry'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(duesRepositoryProvider).deleteDue(due.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete entry: $error')),
        );
      }
    }
  }

  void _editDueEntry(Due due) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => DueDetailScreen(due: due)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expensesAsyncValue = ref.watch(personalExpensesStreamProvider);
    final duesAsyncValue = ref.watch(duesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Personal Expenses')),
      body: expensesAsyncValue.when(
        data: (expenses) => duesAsyncValue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('Error: $error')),
          data: (dues) {
            final monthExpenses = expenses.where((expense) {
              return expense.expenseDate.year == _selectedMonth.year &&
                  expense.expenseDate.month == _selectedMonth.month;
            }).toList();
            final monthDues = dues.where((due) {
              return due.transactionDate.year == _selectedMonth.year &&
                  due.transactionDate.month == _selectedMonth.month;
            }).toList();
            final expenseTotal = monthExpenses.fold<double>(
              0,
              (sum, expense) => sum + expense.amount,
            );
            final peopleAdjustment = monthDues.fold<double>(0, (sum, due) {
              return sum + (due.direction == 'lent' ? due.amount : -due.amount);
            });
            final total = expenseTotal + peopleAdjustment;
            final totalLabel = total < 0
                ? '-₹${total.abs().toStringAsFixed(2)}'
                : '₹${total.toStringAsFixed(2)}';
            final categoryTotals = <String, double>{};
            for (final expense in monthExpenses) {
              final category = expense.category?.trim().isNotEmpty == true
                  ? expense.category!.trim()
                  : 'General';
              categoryTotals[category] =
                  (categoryTotals[category] ?? 0) + expense.amount;
            }
            if (peopleAdjustment != 0) {
              categoryTotals['People balances'] = peopleAdjustment;
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _monthLabel(_selectedMonth),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Net expenses in ${_monthLabel(_selectedMonth)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                totalLabel,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${monthExpenses.length + monthDues.length} entries',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Category Breakdown',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (categoryTotals.isEmpty)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No expenses recorded for this month yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: categoryTotals.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(entry.key)),
                                Text(
                                  '${entry.value < 0 ? '−' : ''}₹${entry.value.abs().toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Transactions',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (monthExpenses.isEmpty && monthDues.isEmpty)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'Add an expense to start tracking your monthly spending.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                if (monthExpenses.isNotEmpty || monthDues.isNotEmpty)
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 360,
                      child: ListView.separated(
                        key: const ValueKey('expense-entries-scroll'),
                        padding: const EdgeInsets.all(8),
                        itemCount: monthDues.length + monthExpenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          if (index < monthDues.length) {
                            final due = monthDues[index];
                            final theyOweYou = due.direction == 'lent';
                            final signedAmount = theyOweYou
                                ? due.amount
                                : -due.amount;
                            final color = theyOweYou
                                ? Colors.green
                                : Colors.redAccent;
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.1),
                                  child: Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: color,
                                  ),
                                ),
                                title: Text(
                                  theyOweYou
                                      ? '${due.personName} owes you'
                                      : 'You owe ${due.personName}',
                                ),
                                subtitle: Text(
                                  '${due.reason?.trim().isNotEmpty == true ? '${due.reason} · ' : ''}${due.transactionDate.day}/${due.transactionDate.month}/${due.transactionDate.year}${due.status == 'settled' ? ' · Settled' : ' · Open'}',
                                ),
                                onTap: () => _editDueEntry(due),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${signedAmount < 0 ? '−' : '+'}₹${signedAmount.abs().toStringAsFixed(2)}',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: color,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Person entry actions',
                                      onSelected: (action) {
                                        if (action == 'edit') {
                                          _editDueEntry(due);
                                        }
                                        if (action == 'delete') {
                                          _deleteDueEntry(due);
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
                                  ],
                                ),
                              ),
                            );
                          }
                          final expense =
                              monthExpenses[index - monthDues.length];
                          final category =
                              expense.category?.trim().isNotEmpty == true
                              ? expense.category!.trim()
                              : 'General';
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.1),
                                child: Icon(
                                  Icons.receipt_long_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                expense.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$category · ${expense.expenseDate.day}/${expense.expenseDate.month}/${expense.expenseDate.year}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '₹${expense.amount.toStringAsFixed(2)}',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Expense actions',
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AddPersonalExpenseScreen(
                                                  expense: expense,
                                                ),
                                          ),
                                        );
                                      } else if (action == 'delete') {
                                        _deletePersonalExpense(expense);
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
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddPersonalExpenseScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
    );
  }
}

class AddPersonalExpenseScreen extends ConsumerStatefulWidget {
  const AddPersonalExpenseScreen({super.key, this.expense});

  final PersonalExpense? expense;

  @override
  ConsumerState<AddPersonalExpenseScreen> createState() =>
      _AddPersonalExpenseScreenState();
}

class _AddPersonalExpenseScreenState
    extends ConsumerState<AddPersonalExpenseScreen> {
  static const _categories = [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Health',
    'Education',
    'Entertainment',
    'General',
  ];

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'General';
  DateTime _expenseDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _amountController.text = expense.amount.toStringAsFixed(2);
      _descriptionController.text = expense.description;
      _category = expense.category?.trim().isNotEmpty == true
          ? expense.category!.trim()
          : 'General';
      _expenseDate = expense.expenseDate;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(personalExpensesRepositoryProvider);
      if (widget.expense case final expense?) {
        await repository.updateExpense(
          expense.id,
          amount: double.parse(_amountController.text.trim()),
          description: _descriptionController.text.trim(),
          category: _category,
          expenseDate: _expenseDate,
        );
      } else {
        await repository.createExpense(
          amount: double.parse(_amountController.text.trim()),
          description: _descriptionController.text.trim(),
          category: _category,
          expenseDate: _expenseDate,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save expense: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Add Expense' : 'Edit Expense'),
        actions: [
          IconButton(
            tooltip: widget.expense == null ? 'Save expense' : 'Update expense',
            onPressed: _isSaving ? null : _saveExpense,
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              validator: (value) {
                final amount = double.tryParse(value?.trim() ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter an amount greater than zero';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a description'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.calendar_month_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Expense date'),
                subtitle: Text(
                  '${_expenseDate.day}/${_expenseDate.month}/${_expenseDate.year}',
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _expenseDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => _expenseDate = date);
                },
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveExpense,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Save Expense'),
            ),
          ],
        ),
      ),
    );
  }
}
