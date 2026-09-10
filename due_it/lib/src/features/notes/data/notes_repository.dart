import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Note {
  final String id;
  final String userId;
  final String? title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.userId,
    this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class NotesRepository {
  final SupabaseClient _client;

  NotesRepository(this._client);

  Stream<List<Note>> watchNotes() {
    return _client
        .from('notes')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .map((data) => data.map((json) => Note.fromJson(json)).toList());
  }

  Future<void> createNote({String? title, required String content}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('notes').insert({
      'user_id': userId,
      'title': title,
      'content': content,
    });
  }

  Future<void> updateNote(String id, {String? title, required String content}) async {
    final updates = <String, dynamic>{
      'content': content,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (title != null) updates['title'] = title;

    await _client.from('notes').update(updates).eq('id', id);
  }

  Future<void> deleteNote(String id) async {
    await _client.from('notes').delete().eq('id', id);
  }
}

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(Supabase.instance.client);
});

final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchNotes();
});
