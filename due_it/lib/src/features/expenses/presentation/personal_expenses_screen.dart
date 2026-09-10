import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/personal_expenses_repository.dart';

class PersonalExpensesScreen extends ConsumerWidget {
  const PersonalExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsyncValue = ref.watch(personalExpensesStreamProvider);

    return Scaffold(
      body: expensesAsyncValue.when(
        data: (expenses) {
          if (expenses.isEmpty) {
            return const Center(child: Text('No personal expenses logged yet.'));
          }

          final Map<String, double> categoryTotals = {};
          for (var expense in expenses) {
            final cat = expense.category ?? 'Uncategorized';
            categoryTotals[cat] = (categoryTotals[cat] ?? 0) + expense.amount;
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Category Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 8),
                        ...categoryTotals.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key),
                              Text('\{e.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.receipt)),
                      title: Text('\{expense.amount.toStringAsFixed(2)} - '),
                      subtitle: Text(' - '),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          ref.read(personalExpensesRepositoryProvider).deleteExpense(expense.id);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: ')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Open add personal expense dialog
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
