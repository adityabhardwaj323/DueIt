import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Note {
  final String id;
  final String userId;
  final String? title;
  final String content;
  final bool isChecklist;
  final List<NoteChecklistItem> checklistItems;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.userId,
    this.title,
    required this.content,
    this.isChecklist = false,
    this.checklistItems = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      content: json['content'],
      isChecklist: json['note_type'] == 'checklist',
      checklistItems: ((json['checklist_items'] as List<dynamic>?) ?? const [])
          .map(
            (item) => NoteChecklistItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }
}

class NoteChecklistItem {
  final String text;
  final bool isChecked;

  const NoteChecklistItem({required this.text, this.isChecked = false});

  factory NoteChecklistItem.fromJson(Map<String, dynamic> json) {
    return NoteChecklistItem(
      text: json['text'] as String? ?? '',
      isChecked: json['is_checked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {'text': text, 'is_checked': isChecked};
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

  Future<void> createNote({
    String? title,
    required String content,
    bool isChecklist = false,
    List<NoteChecklistItem> checklistItems = const [],
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.from('notes').insert({
      'user_id': userId,
      'title': title,
      'content': content,
      'note_type': isChecklist ? 'checklist' : 'text',
      'checklist_items': checklistItems.map((item) => item.toJson()).toList(),
    });
  }

  Future<void> updateNote(
    String id, {
    String? title,
    required String content,
    bool isChecklist = false,
    List<NoteChecklistItem> checklistItems = const [],
  }) async {
    final updates = <String, dynamic>{
      'title': title,
      'content': content,
      'note_type': isChecklist ? 'checklist' : 'text',
      'checklist_items': checklistItems.map((item) => item.toJson()).toList(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

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
