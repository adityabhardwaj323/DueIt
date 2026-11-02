import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_repository.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isListView = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatNoteDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return mins <= 1 ? 'Just now' : '$mins mins ago';
    }
    if (diff.inHours < 24) {
      final hrs = diff.inHours;
      return '$hrs hour${hrs == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      final days = diff.inDays;
      return '$days day${days == 1 ? '' : 's'} ago';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notesAsyncValue = ref.watch(notesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.sticky_note_2_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Notes'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isListView
                ? 'Switch to grid view'
                : 'Switch to list view',
            onPressed: () => setState(() => _isListView = !_isListView),
            icon: Icon(
              _isListView ? Icons.grid_view_rounded : Icons.view_agenda_rounded,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: notesAsyncValue.when(
        data: (notes) {
          if (notes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.note_alt_outlined,
                        size: 54,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No notes yet',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Capture your thoughts, quick reminders, and ideas.\nTap + to write your first note.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final query = _searchQuery.trim().toLowerCase();
          final filteredNotes = query.isEmpty
              ? notes
              : notes.where((n) {
                  final titleMatch =
                      n.title?.toLowerCase().contains(query) ?? false;
                  final contentMatch = n.content.toLowerCase().contains(query);
                  return titleMatch || contentMatch;
                }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search your notes',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(isDark ? 0.35 : 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.5),
                      ),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              if (filteredNotes.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No notes found for "$_searchQuery"',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _isListView
                          ? 1
                          : MediaQuery.sizeOf(context).width >= 700
                          ? 3
                          : 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: _isListView
                          ? MediaQuery.sizeOf(context).width / 112
                          : 0.92,
                    ),
                    itemCount: filteredNotes.length,
                    itemBuilder: (context, index) {
                      final note = filteredNotes[index];
                      final hasTitle =
                          note.title != null && note.title!.trim().isNotEmpty;
                      final cardColors = isDark
                          ? const [
                              Color(0xFF33352F),
                              Color(0xFF30363A),
                              Color(0xFF393432),
                              Color(0xFF34313A),
                            ]
                          : const [
                              Color(0xFFFFF8D8),
                              Color(0xFFE8F4EA),
                              Color(0xFFEAF2FC),
                              Color(0xFFFCEBE5),
                            ];
                      final previewContent = note.isChecklist
                          ? note.checklistItems
                                .map(
                                  (item) =>
                                      '${item.isChecked ? '☑' : '☐'} ${item.text}',
                                )
                                .join('\n')
                          : note.content.trim();
                      return Material(
                        color: _isListView
                            ? theme.cardColor
                            : cardColors[index % cardColors.length],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: _isListView
                              ? BorderSide(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.4,
                                  ),
                                )
                              : BorderSide.none,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NoteDetailScreen(note: note),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasTitle ? note.title!.trim() : 'Untitled',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                if (previewContent.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Text(
                                      previewContent,
                                      maxLines: _isListView ? 2 : 7,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            height: 1.4,
                                            color: isDark
                                                ? const Color(0xFFE0E0DC)
                                                : const Color(0xFF4A4A46),
                                          ),
                                    ),
                                  ),
                                ] else
                                  const Spacer(),
                                const SizedBox(height: 8),
                                Text(
                                  _formatNoteDate(note.updatedAt),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isDark
                                        ? const Color(0xFFB7B9B1)
                                        : const Color(0xFF74766F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Error loading notes: $error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NoteDetailScreen()));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Note'),
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
  late List<_ChecklistDraft> _checklistDrafts;
  late bool _isChecklist;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(
      text: widget.note?.content ?? '',
    );
    _isChecklist = widget.note?.isChecklist ?? false;
    _checklistDrafts =
        widget.note?.checklistItems
            .map((item) => _ChecklistDraft(item.text, item.isChecked))
            .toList() ??
        [];
    if (_isChecklist && _checklistDrafts.isEmpty) {
      _checklistDrafts = [_ChecklistDraft('')];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    for (final item in _checklistDrafts) {
      item.dispose();
    }
    super.dispose();
  }

  void _setChecklistMode(bool value) {
    if (_isChecklist == value) return;
    setState(() {
      if (value) {
        final lines = _contentController.text
            .split('\n')
            .where((line) => line.trim().isNotEmpty);
        _checklistDrafts = lines.map((line) => _ChecklistDraft(line)).toList();
        if (_checklistDrafts.isEmpty) {
          _checklistDrafts.add(_ChecklistDraft(''));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _checklistDrafts.isNotEmpty) {
            _checklistDrafts.first.focusNode.requestFocus();
          }
        });
      } else {
        _contentController.text = _checklistDrafts
            .map((item) => item.controller.text.trim())
            .where((line) => line.isNotEmpty)
            .join('\n');
        for (final item in _checklistDrafts) {
          item.dispose();
        }
        _checklistDrafts = [];
      }
      _isChecklist = value;
    });
  }

  void _addChecklistItem() {
    final item = _ChecklistDraft('');
    setState(() => _checklistDrafts.add(item));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) item.focusNode.requestFocus();
    });
  }

  Future<void> _saveNote() async {
    final checklistItems = _isChecklist
        ? _checklistDrafts
              .where((item) => item.controller.text.trim().isNotEmpty)
              .map(
                (item) => NoteChecklistItem(
                  text: item.controller.text.trim(),
                  isChecked: item.isChecked,
                ),
              )
              .toList()
        : <NoteChecklistItem>[];
    final content = _isChecklist
        ? checklistItems.map((item) => item.text).join('\n')
        : _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note content cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final repo = ref.read(notesRepositoryProvider);
    final title = _titleController.text.trim().isEmpty
        ? null
        : _titleController.text.trim();

    try {
      if (widget.note == null) {
        await repo.createNote(
          title: title,
          content: content,
          isChecklist: _isChecklist,
          checklistItems: checklistItems,
        );
      } else {
        await repo.updateNote(
          widget.note!.id,
          title: title,
          content: content,
          isChecklist: _isChecklist,
          checklistItems: checklistItems,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save note: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text(
          'Are you sure you want to delete this note? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(notesRepositoryProvider).deleteNote(widget.note!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        actions: [
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.check_rounded),
                    tooltip: 'Save',
                    onPressed: _saveNote,
                  ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Note Title',
                hintStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF9CA3AF),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const Divider(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.notes_rounded),
                  label: Text('Text'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.checklist_rounded),
                  label: Text('Checklist'),
                ),
              ],
              selected: {_isChecklist},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _setChecklistMode(selection.first),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isChecklist
                  ? ListView.builder(
                      itemCount: _checklistDrafts.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _checklistDrafts.length) {
                          return TextButton.icon(
                            onPressed: _addChecklistItem,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add item'),
                          );
                        }
                        final item = _checklistDrafts[index];
                        return Row(
                          key: ObjectKey(item),
                          children: [
                            Checkbox(
                              value: item.isChecked,
                              onChanged: (checked) => setState(
                                () => item.isChecked = checked ?? false,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                key: ObjectKey(item.controller),
                                controller: item.controller,
                                focusNode: item.focusNode,
                                autofocus:
                                    index == 0 && item.controller.text.isEmpty,
                                decoration: const InputDecoration(
                                  hintText: 'List item',
                                  border: InputBorder.none,
                                ),
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _addChecklistItem(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove item',
                              onPressed: () => setState(() {
                                _checklistDrafts.removeAt(index);
                                item.dispose();
                              }),
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        );
                      },
                    )
                  : TextField(
                      controller: _contentController,
                      decoration: InputDecoration(
                        hintText: 'Type your note here...',
                        hintStyle: TextStyle(
                          fontSize: 16,
                          color: isDark
                              ? const Color(0xFF6B7280)
                              : const Color(0xFF9CA3AF),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(fontSize: 16, height: 1.5),
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

class _ChecklistDraft {
  final TextEditingController controller;
  final FocusNode focusNode = FocusNode();
  bool isChecked;

  _ChecklistDraft(String text, [this.isChecked = false])
    : controller = TextEditingController(text: text);

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
