import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notes_repository.dart';

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsyncValue = ref.watch(notesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
      ),
      body: notesAsyncValue.when(
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('No notes yet. Create one!'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(note.title ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    note.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => NoteDetailScreen(note: note),
                    ));
                  },
                ),
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
            builder: (_) => const NoteDetailScreen(),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class NoteDetailScreen extends ConsumerStatefulWidget {
  final Note? note;

  const NoteDetailScreen({super.key, this.note});

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return; // Prevent empty content

    final repo = ref.read(notesRepositoryProvider);
    if (widget.note == null) {
      await repo.createNote(
        title: _titleController.text.isEmpty ? null : _titleController.text,
        content: content,
      );
    } else {
      await repo.updateNote(
        widget.note!.id,
        title: _titleController.text.isEmpty ? null : _titleController.text,
        content: content,
      );
    }
    
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        actions: [
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await ref.read(notesRepositoryProvider).deleteNote(widget.note!.id);
                if (mounted) Navigator.of(context).pop();
              },
            ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveNote,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration(
                  hintText: 'Note content (supports basic formatting later)...',
                  border: InputBorder.none,
                ),
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
