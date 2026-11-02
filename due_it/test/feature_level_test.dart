import 'package:due_it/src/core/theme/app_theme.dart';
import 'package:due_it/src/core/theme/theme_provider.dart';
import 'package:due_it/src/core/utils/app_timezone.dart';
import 'package:due_it/src/features/auth/presentation/auth_screen.dart';
import 'package:due_it/src/features/expenses/data/dues_repository.dart';
import 'package:due_it/src/features/expenses/data/personal_expenses_repository.dart';
import 'package:due_it/src/features/expenses/presentation/dues_screen.dart';
import 'package:due_it/src/features/expenses/presentation/personal_expenses_screen.dart';
import 'package:due_it/src/features/home/presentation/smart_inbox_screen.dart';
import 'package:due_it/src/features/notes/data/notes_repository.dart';
import 'package:due_it/src/features/notes/presentation/notes_screen.dart';
import 'package:due_it/src/features/tasks/data/streak_tasks_repository.dart';
import 'package:due_it/src/features/tasks/data/tasks_repository.dart';
import 'package:due_it/src/features/tasks/presentation/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(AppTimezone.initialize);

  group('Feature data models', () {
    final created = DateTime.utc(2026, 10, 28, 12);

    test('task maps optional fields, completion and local dates', () {
      final task = Task.fromJson({
        'id': 'task-1',
        'user_id': 'user-1',
        'title': 'Plan the week',
        'description': 'Review priorities',
        'due_date': '2026-10-29T12:00:00Z',
        'priority': 'high',
        'is_completed': true,
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
      });

      expect(task.title, 'Plan the week');
      expect(task.description, 'Review priorities');
      expect(task.priority, 'high');
      expect(task.isCompleted, isTrue);
      expect(task.dueDate, DateTime.parse('2026-10-29T12:00:00Z').toLocal());
    });

    test(
      'streak task applies defaults and parses the last completion date',
      () {
        final streak = StreakTask.fromJson({
          'id': 'streak-1',
          'user_id': 'user-1',
          'title': 'Read',
          'last_completed_date': '2026-10-27T18:30:00Z',
          'created_at': created.toIso8601String(),
          'updated_at': created.toIso8601String(),
        });

        expect(streak.currentStreak, 0);
        expect(streak.bestStreak, 0);
        expect(streak.lastCompletedDate, isNotNull);
      },
    );

    test('note maps title, content and timestamps', () {
      final note = Note.fromJson({
        'id': 'note-1',
        'user_id': 'user-1',
        'title': 'Weekend ideas',
        'content': 'Visit the museum',
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
      });

      expect(note.title, 'Weekend ideas');
      expect(note.content, 'Visit the museum');
      expect(note.createdAt, created.toLocal());
    });

    test('due maps direction, amount, optional due date and defaults', () {
      final due = Due.fromJson({
        'id': 'due-1',
        'user_id': 'user-1',
        'direction': 'lent',
        'person_name': 'Maya',
        'amount': 2500,
        'transaction_date': created.toIso8601String(),
        'due_date': '2026-11-01T10:00:00Z',
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
      });

      expect(due.direction, 'lent');
      expect(due.amount, 2500.0);
      expect(due.status, 'pending');
      expect(due.isRecurring, isFalse);
      expect(due.dueDate, isNotNull);
    });

    test('personal expense maps amount, category and date', () {
      final expense = PersonalExpense.fromJson({
        'id': 'expense-1',
        'user_id': 'user-1',
        'amount': 340.5,
        'description': 'Groceries',
        'category': 'Food',
        'expense_date': created.toIso8601String(),
        'created_at': created.toIso8601String(),
        'updated_at': created.toIso8601String(),
      });

      expect(expense.amount, 340.5);
      expect(expense.description, 'Groceries');
      expect(expense.category, 'Food');
      expect(expense.expenseDate, created.toLocal());
    });
  });

  group('Timezone and themes', () {
    test('business event times convert IST to UTC consistently', () {
      final event = AppTimezone.createBusinessEventTime(2026, 10, 28, 9, 0);

      expect(event, DateTime.utc(2026, 10, 28, 3, 30));
      expect(AppTimezone.dateKey(event), '2026-10-28');
    });

    test('all theme choices resolve and invalid IDs fall back safely', () {
      expect(AppThemeKey.values, hasLength(6));
      for (final key in AppThemeKey.values) {
        expect(AppThemeKeyExtension.fromId(key.id), key);
        expect(key.previewColor.alpha, 255);
        expect(AppTheme.getTheme(key).brightness, isNotNull);
      }
      expect(
        AppThemeKeyExtension.fromId('missing'),
        AppThemeKey.modernLavender,
      );
      expect(AppThemeKeyExtension.fromId(null), AppThemeKey.modernLavender);
    });

    test(
      'selected theme updates app state and persists the preference',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(themeProvider.notifier)
            .setTheme(AppThemeKey.calmMint);

        expect(container.read(themeProvider), AppThemeKey.calmMint);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('selected_app_theme'), 'calmMint');
      },
    );
  });

  group('Repository authentication boundaries', () {
    test('task creation and completion reject a missing session', () async {
      final repository = TasksRepository(_testClient());

      await expectLater(
        repository.createTask(title: 'Private task'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.updateTaskStatus('task-1', true),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.deleteTask('task-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('note creation rejects a missing session', () async {
      final repository = NotesRepository(_testClient());

      await expectLater(
        repository.createNote(content: 'Private note'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'due creation, settlement and deletion reject a missing session',
      () async {
        final repository = DuesRepository(_testClient());

        await expectLater(
          repository.createDue(
            direction: 'lent',
            personName: 'Maya',
            amount: 100,
            transactionDate: DateTime.utc(2026, 10, 28),
          ),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          repository.settleDue('due-1'),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          repository.deleteDue('due-1'),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('personal expense creation rejects a missing session', () async {
      final repository = PersonalExpensesRepository(_testClient());

      await expectLater(
        repository.createExpense(
          amount: 100,
          description: 'Private expense',
          expenseDate: DateTime.utc(2026, 10, 28),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('streak creation and completion reject a missing session', () async {
      final repository = StreakTasksRepository(_testClient());

      await expectLater(
        repository.createStreakTask('Read'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.completeStreakTask('streak-1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Feature screens', () {
    final now = DateTime.now();
    final task = Task(
      id: 'task-1',
      userId: 'user-1',
      title: 'Review project plan',
      description: 'Confirm the next milestone',
      dueDate: now.add(const Duration(days: 1)),
      priority: 'high',
      createdAt: now,
      updatedAt: now,
    );
    final completedTask = Task(
      id: 'task-2',
      userId: 'user-1',
      title: 'Reply to the team',
      isCompleted: true,
      createdAt: now,
      updatedAt: now,
    );
    final note = Note(
      id: 'note-1',
      userId: 'user-1',
      title: 'Weekend plans',
      content: 'Visit the museum',
      createdAt: now,
      updatedAt: now,
    );
    final due = Due(
      id: 'due-1',
      userId: 'user-1',
      direction: 'lent',
      personName: 'Maya',
      amount: 2500,
      reason: 'Trip tickets',
      transactionDate: now,
      dueDate: now.add(const Duration(days: 3)),
      createdAt: now,
      updatedAt: now,
    );
    final expense = PersonalExpense(
      id: 'expense-1',
      userId: 'user-1',
      amount: 340.5,
      description: 'Groceries',
      category: 'Food',
      expenseDate: now,
      createdAt: now,
      updatedAt: now,
    );

    testWidgets('sign-in form validates missing credentials locally', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
      await tester.tap(find.text('Sign In').last);
      await tester.pump();

      expect(find.text('Please enter both email and password'), findsOneWidget);
    });

    testWidgets('tasks screen separates pending and completed tasks', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksStreamProvider.overrideWith(
              (ref) => Stream.value([task, completedTask]),
            ),
          ],
          child: const MaterialApp(home: TasksScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review project plan'), findsOneWidget);
      expect(find.text('Reply to the team'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Scheduled Tasks'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
    });

    testWidgets('notes screen displays searchable note content', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesStreamProvider.overrideWith((ref) => Stream.value([note])),
          ],
          child: const MaterialApp(home: NotesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekend plans'), findsOneWidget);
      expect(find.text('Visit the museum'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('dues screen groups repeated transactions into one account', (
      tester,
    ) async {
      final secondDue = Due(
        id: 'due-2',
        userId: 'user-1',
        direction: 'borrowed',
        personName: 'maya',
        amount: 500,
        reason: 'Cab fare',
        transactionDate: now,
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duesStreamProvider.overrideWith(
              (ref) => Stream.value([due, secondDue]),
            ),
          ],
          child: const MaterialApp(home: DuesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('They owe you · 2 open entries'), findsOneWidget);
      expect(find.text('₹2000.00'), findsOneWidget);

      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      expect(find.text('Open transactions'), findsOneWidget);
      expect(find.text('2 entries'), findsOneWidget);
      expect(find.textContaining('Trip tickets'), findsOneWidget);
      expect(find.textContaining('Cab fare'), findsOneWidget);
      expect(find.text('Add transaction'), findsOneWidget);
    });

    testWidgets('dues screen shows zero owed and borrowed balances', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duesStreamProvider.overrideWith((ref) => Stream.value(<Due>[])),
          ],
          child: const MaterialApp(home: DuesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You owe'), findsOneWidget);
      expect(find.text('Owed to you'), findsOneWidget);
      expect(find.text('₹0.00'), findsNWidgets(2));
    });

    testWidgets('personal expenses show category totals and entries', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duesStreamProvider.overrideWith((ref) => Stream.value(<Due>[])),
            personalExpensesStreamProvider.overrideWith(
              (ref) => Stream.value([expense]),
            ),
          ],
          child: const MaterialApp(home: PersonalExpensesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Category Breakdown'), findsOneWidget);
      expect(find.textContaining('Net expenses in'), findsOneWidget);
      expect(find.text('₹340.50'), findsAtLeastNWidgets(1));
      expect(find.text('Food'), findsOneWidget);
      expect(find.textContaining('Groceries'), findsOneWidget);
    });

    testWidgets('person balances adjust monthly expense total by direction', (
      tester,
    ) async {
      final lent = Due(
        id: 'due-lent',
        userId: 'user-1',
        direction: 'lent',
        personName: 'Maya',
        amount: 70,
        reason: 'Shared groceries',
        transactionDate: now,
        status: 'settled',
        createdAt: now,
        updatedAt: now,
      );
      final borrowed = Due(
        id: 'due-borrowed',
        userId: 'user-1',
        direction: 'borrowed',
        personName: 'Maya',
        amount: 20,
        reason: 'Paid her back',
        transactionDate: now,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalExpensesStreamProvider.overrideWith(
              (ref) => Stream.value([expense]),
            ),
            duesStreamProvider.overrideWith(
              (ref) => Stream.value([lent, borrowed]),
            ),
          ],
          child: const MaterialApp(home: PersonalExpensesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('₹390.50'), findsOneWidget);
      expect(find.text('People balances'), findsOneWidget);
      expect(find.text('Maya owes you'), findsOneWidget);
      expect(find.text('You owe Maya'), findsOneWidget);
      expect(find.text('+₹70.00'), findsOneWidget);
      expect(find.text('−₹20.00'), findsOneWidget);
    });

    testWidgets('personal expense delete action calls the repository', (
      tester,
    ) async {
      final repository = _RecordingExpensesRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalExpensesRepositoryProvider.overrideWithValue(repository),
            duesStreamProvider.overrideWith((ref) => Stream.value(<Due>[])),
            personalExpensesStreamProvider.overrideWith(
              (ref) => Stream.value([expense]),
            ),
          ],
          child: const MaterialApp(home: PersonalExpensesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expense actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(repository.deletedExpenseId, 'expense-1');
    });

    testWidgets('personal expense can be edited from its entry menu', (
      tester,
    ) async {
      final repository = _RecordingExpensesRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalExpensesRepositoryProvider.overrideWithValue(repository),
            duesStreamProvider.overrideWith((ref) => Stream.value(<Due>[])),
            personalExpensesStreamProvider.overrideWith(
              (ref) => Stream.value([expense]),
            ),
          ],
          child: const MaterialApp(home: PersonalExpensesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expense actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '88.25');
      await tester.enterText(find.byType(TextFormField).at(1), 'Updated lunch');
      await tester.tap(find.byTooltip('Update expense'));
      await tester.pumpAndSettle();

      expect(repository.updatedExpenseId, expense.id);
      expect(repository.updatedExpenseAmount, 88.25);
      expect(repository.updatedExpenseDescription, 'Updated lunch');
    });

    testWidgets('personal expense form creates a monthly expense', (
      tester,
    ) async {
      final repository = _RecordingExpensesRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalExpensesRepositoryProvider.overrideWithValue(repository),
            duesStreamProvider.overrideWith((ref) => Stream.value(<Due>[])),
            personalExpensesStreamProvider.overrideWith(
              (ref) => Stream.value(<PersonalExpense>[]),
            ),
          ],
          child: const MaterialApp(home: PersonalExpensesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '125.50');
      await tester.enterText(find.byType(TextFormField).at(1), 'Lunch');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(repository.createdAmount, 125.5);
      expect(repository.createdDescription, 'Lunch');
    });

    testWidgets('smart inbox combines urgent tasks, dues and recent notes', (
      tester,
    ) async {
      final urgentTask = Task(
        id: 'urgent-task',
        userId: 'user-1',
        title: 'Prepare presentation',
        dueDate: now.add(const Duration(hours: 2)),
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesStreamProvider.overrideWith((ref) => Stream.value([note])),
            tasksStreamProvider.overrideWith(
              (ref) => Stream.value([urgentTask]),
            ),
            duesStreamProvider.overrideWith((ref) => Stream.value([due])),
          ],
          child: const MaterialApp(home: SmartInboxScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Smart Inbox'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
      expect(find.text('₹2500'), findsAtLeastNWidgets(1));
      expect(find.text('Weekend plans'), findsOneWidget);
    });

    testWidgets('task checkbox calls the completion repository action', (
      tester,
    ) async {
      final repository = _RecordingTasksRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksRepositoryProvider.overrideWithValue(repository),
            tasksStreamProvider.overrideWith((ref) => Stream.value([task])),
          ],
          child: const MaterialApp(home: TasksScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(repository.updatedTaskId, 'task-1');
      expect(repository.completedValue, isTrue);
    });

    testWidgets('task creation form validates a title and submits the task', (
      tester,
    ) async {
      final repository = _RecordingTasksRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksRepositoryProvider.overrideWithValue(repository),
            tasksStreamProvider.overrideWith((ref) => Stream.value(<Task>[])),
          ],
          child: const MaterialApp(home: TasksScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save'));
      await tester.pump();
      expect(find.text('Please enter a task title'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'Ship release notes',
      );
      await tester.tap(find.text('In 8 hours'));
      await tester.tap(find.text('Create Task'));
      await tester.pumpAndSettle();

      expect(repository.createdTitle, 'Ship release notes');
      expect(repository.createdDueDate, isNotNull);
      expect(
        repository.createdDueDate!.difference(DateTime.now()).inHours,
        inInclusiveRange(7, 8),
      );
      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('task editor updates an existing task', (tester) async {
      final repository = _RecordingTasksRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksRepositoryProvider.overrideWithValue(repository),
            tasksStreamProvider.overrideWith((ref) => Stream.value([task])),
          ],
          child: const MaterialApp(home: TasksScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review project plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Updated plan');
      await tester.tap(find.text('No date'));
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updatedTaskId, 'task-1');
      expect(repository.updatedTitle, 'Updated plan');
      expect(repository.clearDueDate, isTrue);
    });

    testWidgets('task deletion requires confirmation and deletes the item', (
      tester,
    ) async {
      final repository = _RecordingTasksRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksRepositoryProvider.overrideWithValue(repository),
            tasksStreamProvider.overrideWith((ref) => Stream.value([task])),
          ],
          child: const MaterialApp(home: TasksScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review project plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(repository.deletedTaskId, 'task-1');
    });

    testWidgets('note editor rejects empty content and submits a note', (
      tester,
    ) async {
      final repository = _RecordingNotesRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(repository),
            notesStreamProvider.overrideWith((ref) => Stream.value(<Note>[])),
          ],
          child: const MaterialApp(home: NotesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save'));
      await tester.pump();
      expect(find.text('Note content cannot be empty'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Weekend ideas');
      await tester.enterText(fields.at(1), 'Visit the museum');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(repository.createdTitle, 'Weekend ideas');
      expect(repository.createdContent, 'Visit the museum');
    });

    testWidgets(
      'note editor updates and confirms deletion of an existing note',
      (tester) async {
        final repository = _RecordingNotesRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              notesRepositoryProvider.overrideWithValue(repository),
              notesStreamProvider.overrideWith((ref) => Stream.value([note])),
            ],
            child: const MaterialApp(home: NotesScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekend plans'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), 'Updated weekend');
        await tester.enterText(find.byType(TextField).at(1), 'Go hiking');
        await tester.tap(find.byTooltip('Save'));
        await tester.pumpAndSettle();

        expect(repository.updatedNoteId, 'note-1');
        expect(repository.updatedTitle, 'Updated weekend');
        expect(repository.updatedContent, 'Go hiking');

        await tester.tap(find.text('Weekend plans'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        expect(repository.deletedNoteId, 'note-1');
      },
    );

    testWidgets('due form validates and records a new lent transaction', (
      tester,
    ) async {
      final repository = _RecordingDuesRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duesRepositoryProvider.overrideWithValue(repository),
            duesStreamProvider.overrideWith((ref) => Stream.value(<Due>[])),
          ],
          child: const MaterialApp(home: DuesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Due'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Transaction'));
      await tester.pump();
      expect(find.text('Please enter person\'s name'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Person Name'),
        'Maya',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (₹)'),
        '750',
      );
      await tester.tap(find.text('Record Transaction'));
      await tester.pumpAndSettle();

      expect(repository.createdPersonName, 'Maya');
      expect(repository.createdAmount, 750);
      expect(repository.createdDirection, 'lent');
    });

    testWidgets(
      'settling an account closes entries without deleting the person',
      (tester) async {
        final repository = _RecordingDuesRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              duesRepositoryProvider.overrideWithValue(repository),
              duesStreamProvider.overrideWith((ref) => Stream.value([due])),
            ],
            child: const MaterialApp(home: DuesScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Maya'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settle account').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settle account').last);
        await tester.pumpAndSettle();

        expect(repository.settledDueId, 'due-1');
        expect(repository.createNextRecurringOnSettle, isFalse);
        expect(repository.deletedDueId, isNull);
      },
    );

    testWidgets('settled person remains until separately removed', (
      tester,
    ) async {
      final repository = _RecordingDuesRepository();
      final settledDue = Due(
        id: 'due-settled',
        userId: due.userId,
        direction: due.direction,
        personName: due.personName,
        amount: due.amount,
        reason: due.reason,
        transactionDate: due.transactionDate,
        dueDate: due.dueDate,
        status: 'settled',
        createdAt: due.createdAt,
        updatedAt: due.updatedAt,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duesRepositoryProvider.overrideWithValue(repository),
            duesStreamProvider.overrideWith(
              (ref) => Stream.value([settledDue]),
            ),
          ],
          child: const MaterialApp(home: DuesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settled'), findsOneWidget);
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No open entries'), findsOneWidget);
      expect(find.textContaining('Trip tickets'), findsNothing);
      expect(find.text('Remove person & history'), findsOneWidget);
      await tester.tap(find.text('Remove person & history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove person').last);
      await tester.pumpAndSettle();

      expect(repository.deletedDueId, settledDue.id);
    });

    testWidgets('due editor updates and confirms deletion of an entry', (
      tester,
    ) async {
      final repository = _RecordingDuesRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duesRepositoryProvider.overrideWithValue(repository),
            duesStreamProvider.overrideWith((ref) => Stream.value([due])),
          ],
          child: const MaterialApp(home: DuesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('They owe me · ₹2500.00'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Due Entry'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Maya Singh');
      await tester.enterText(find.byType(TextFormField).at(1), '2750');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updatedDueId, 'due-1');
      expect(repository.updatedPersonName, 'Maya Singh');
      expect(repository.updatedAmount, 2750);

      await tester.tap(find.textContaining('They owe me · ₹2500.00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(repository.deletedDueId, 'due-1');
    });
  });
}

class _RecordingTasksRepository extends TasksRepository {
  _RecordingTasksRepository() : super(_testClient());

  String? createdTitle;
  DateTime? createdDueDate;
  String? updatedTaskId;
  String? updatedTitle;
  String? deletedTaskId;
  bool? completedValue;
  bool? clearDueDate;

  @override
  Future<void> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    String? priority,
  }) async {
    createdTitle = title;
    createdDueDate = dueDate;
  }

  @override
  Future<void> updateTaskStatus(String id, bool isCompleted) async {
    updatedTaskId = id;
    completedValue = isCompleted;
  }

  @override
  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? priority,
    bool? isCompleted,
  }) async {
    updatedTaskId = id;
    updatedTitle = title;
    this.clearDueDate = clearDueDate;
  }

  @override
  Future<void> deleteTask(String id) async {
    deletedTaskId = id;
  }
}

class _RecordingNotesRepository extends NotesRepository {
  _RecordingNotesRepository() : super(_testClient());

  String? createdTitle;
  String? createdContent;
  bool? createdIsChecklist;
  List<NoteChecklistItem> createdChecklistItems = [];
  String? updatedNoteId;
  String? updatedTitle;
  String? updatedContent;
  bool? updatedIsChecklist;
  List<NoteChecklistItem> updatedChecklistItems = [];
  String? deletedNoteId;

  @override
  Future<void> createNote({
    String? title,
    required String content,
    bool isChecklist = false,
    List<NoteChecklistItem> checklistItems = const [],
  }) async {
    createdTitle = title;
    createdContent = content;
    createdIsChecklist = isChecklist;
    createdChecklistItems = checklistItems;
  }

  @override
  Future<void> updateNote(
    String id, {
    String? title,
    required String content,
    bool isChecklist = false,
    List<NoteChecklistItem> checklistItems = const [],
  }) async {
    updatedNoteId = id;
    updatedTitle = title;
    updatedContent = content;
    updatedIsChecklist = isChecklist;
    updatedChecklistItems = checklistItems;
  }

  @override
  Future<void> deleteNote(String id) async {
    deletedNoteId = id;
  }
}

class _RecordingDuesRepository extends DuesRepository {
  _RecordingDuesRepository() : super(_testClient());

  String? settledDueId;
  bool? createNextRecurringOnSettle;
  String? createdPersonName;
  double? createdAmount;
  String? createdDirection;
  String? updatedDueId;
  String? updatedPersonName;
  double? updatedAmount;
  String? deletedDueId;

  @override
  Future<void> settleDue(String id, {bool createNextRecurring = true}) async {
    settledDueId = id;
    createNextRecurringOnSettle = createNextRecurring;
  }

  @override
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
    createdDirection = direction;
    createdPersonName = personName;
    createdAmount = amount;
  }

  @override
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
    updatedDueId = id;
    updatedPersonName = personName;
    updatedAmount = amount;
  }

  @override
  Future<void> deleteDue(String id) async {
    deletedDueId = id;
  }
}

class _RecordingExpensesRepository extends PersonalExpensesRepository {
  _RecordingExpensesRepository() : super(_testClient());

  String? deletedExpenseId;
  double? createdAmount;
  String? createdDescription;
  String? updatedExpenseId;
  double? updatedExpenseAmount;
  String? updatedExpenseDescription;

  @override
  Future<void> createExpense({
    required double amount,
    required String description,
    String? category,
    required DateTime expenseDate,
  }) async {
    createdAmount = amount;
    createdDescription = description;
  }

  @override
  Future<void> deleteExpense(String id) async {
    deletedExpenseId = id;
  }

  @override
  Future<void> updateExpense(
    String id, {
    required double amount,
    required String description,
    String? category,
    required DateTime expenseDate,
  }) async {
    updatedExpenseId = id;
    updatedExpenseAmount = amount;
    updatedExpenseDescription = description;
  }
}

SupabaseClient _testClient() => SupabaseClient(
  'http://localhost:54321',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);
