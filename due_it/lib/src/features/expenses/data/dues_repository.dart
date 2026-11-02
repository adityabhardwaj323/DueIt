import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Due {
  final String id;
  final String userId;
  final String direction; // lent, borrowed
  final String personName;
  final String? personEmail;
  final double amount;
  final String? reason;
  final DateTime transactionDate;
  final DateTime? dueDate;
  final String status; // pending, settled, overdue
  final bool isRecurring;
  final String? recurrenceInterval;
  final DateTime createdAt;
  final DateTime updatedAt;

  Due({
    required this.id,
    required this.userId,
    required this.direction,
    required this.personName,
    this.personEmail,
    required this.amount,
    this.reason,
    required this.transactionDate,
    this.dueDate,
    this.status = 'pending',
    this.isRecurring = false,
    this.recurrenceInterval,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Due.fromJson(Map<String, dynamic> json) {
    return Due(
      id: json['id'],
      userId: json['user_id'],
      direction: json['direction'],
      personName: json['person_name'],
      personEmail: json['person_email'],
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'],
      transactionDate: DateTime.parse(json['transaction_date']).toLocal(),
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date']).toLocal()
          : null,
      status: json['status'] ?? 'pending',
      isRecurring: json['is_recurring'] ?? false,
      recurrenceInterval: json['recurrence_interval'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class DuesRepository {
  final SupabaseClient _client;

  DuesRepository(this._client);

  Stream<List<Due>> watchDues() {
    return _client
        .from('dues')
        .stream(primaryKey: ['id'])
        .order('due_date', ascending: true)
        .map((data) => data.map((json) => Due.fromJson(json)).toList());
  }

  Future<void> createDue({
    required String direction,
    required String personName,
    String? personEmail,
    required double amount,
    String? reason,
    required DateTime transactionDate,
    DateTime? dueDate,
    bool isRecurring = false,
    String? recurrenceInterval,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('dues').insert({
      'user_id': userId,
      'direction': direction,
      'person_name': personName,
      'person_email': personEmail,
      'amount': amount,
      'reason': reason,
      'transaction_date': transactionDate.toUtc().toIso8601String(),
      'due_date': dueDate?.toUtc().toIso8601String(),
      'is_recurring': isRecurring,
      'recurrence_interval': recurrenceInterval,
    });
  }

  Future<void> updateDue(
    String id, {
    String? direction,
    String? personName,
    String? personEmail,
    double? amount,
    String? reason,
    DateTime? transactionDate,
    DateTime? dueDate,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (direction != null) updates['direction'] = direction;
    if (personName != null) updates['person_name'] = personName;
    if (personEmail != null) updates['person_email'] = personEmail;
    if (amount != null) updates['amount'] = amount;
    if (reason != null) updates['reason'] = reason;
    if (transactionDate != null)
      updates['transaction_date'] = transactionDate.toUtc().toIso8601String();
    if (dueDate != null)
      updates['due_date'] = dueDate.toUtc().toIso8601String();

    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    await _client
        .from('dues')
        .update(updates)
        .eq('id', id)
        .eq('user_id', userId);
  }

  Future<void> settleDue(String id, {bool createNextRecurring = true}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    final response = await _client
        .from('dues')
        .update({
          'status': 'settled',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select()
        .single();

    // A database trigger atomically cancels pending and leased reminders.

    if (createNextRecurring && response['is_recurring'] == true) {
      final interval = response['recurrence_interval'] as String?;
      final currentDueDateStr = response['due_date'] as String?;

      if (currentDueDateStr != null && interval != null) {
        final currentDue = DateTime.parse(currentDueDateStr).toLocal();
        DateTime nextDue;

        if (interval.toLowerCase() == 'weekly') {
          nextDue = currentDue.add(const Duration(days: 7));
        } else if (interval.toLowerCase() == 'monthly') {
          nextDue = DateTime(
            currentDue.year,
            currentDue.month + 1,
            currentDue.day,
          );
        } else if (interval.toLowerCase() == 'yearly') {
          nextDue = DateTime(
            currentDue.year + 1,
            currentDue.month,
            currentDue.day,
          );
        } else {
          nextDue = currentDue.add(const Duration(days: 30));
        }

        await createDue(
          direction: response['direction'],
          personName: response['person_name'],
          personEmail: response['person_email'],
          amount: (response['amount'] as num).toDouble(),
          reason: response['reason'],
          transactionDate: DateTime.now(),
          dueDate: nextDue,
          isRecurring: true,
          recurrenceInterval: interval,
        );
      }
    }
  }

  Future<void> deleteDue(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('dues').delete().eq('id', id).eq('user_id', userId);
  }
}

final duesRepositoryProvider = Provider<DuesRepository>((ref) {
  return DuesRepository(Supabase.instance.client);
});

final duesStreamProvider = StreamProvider<List<Due>>((ref) {
  final repo = ref.watch(duesRepositoryProvider);
  return repo.watchDues();
});
