import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalExpense {
  final String id;
  final String userId;
  final double amount;
  final String description;
  final String? category;
  final DateTime expenseDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonalExpense({
    required this.id,
    required this.userId,
    required this.amount,
    required this.description,
    this.category,
    required this.expenseDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersonalExpense.fromJson(Map<String, dynamic> json) {
    return PersonalExpense(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] as num).toDouble(),
      description: json['description'],
      category: json['category'],
      expenseDate: DateTime.parse(json['expense_date']).toLocal(),
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class PersonalExpensesRepository {
  final SupabaseClient _client;

  PersonalExpensesRepository(this._client);

  Stream<List<PersonalExpense>> watchPersonalExpenses() {
    return _client
        .from('personal_expenses')
        .stream(primaryKey: ['id'])
        .order('expense_date', ascending: false)
        .map((data) => data.map((json) => PersonalExpense.fromJson(json)).toList());
  }

  Future<void> createExpense({
    required double amount, 
    required String description, 
    String? category, 
    required DateTime expenseDate, 
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('personal_expenses').insert({
      'user_id': userId,
      'amount': amount,
      'description': description,
      'category': category,
      'expense_date': expenseDate.toUtc().toIso8601String(),
    });
  }

  Future<void> deleteExpense(String id) async {
    await _client.from('personal_expenses').delete().eq('id', id);
  }
}

final personalExpensesRepositoryProvider = Provider<PersonalExpensesRepository>((ref) {
  return PersonalExpensesRepository(Supabase.instance.client);
});

final personalExpensesStreamProvider = StreamProvider<List<PersonalExpense>>((ref) {
  final repo = ref.watch(personalExpensesRepositoryProvider);
  return repo.watchPersonalExpenses();
});
