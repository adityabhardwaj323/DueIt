import 'package:due_it/src/features/auth/presentation/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sign up rejects an invalid email before calling auth', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    final toggle = find.text('Don\'t have an account? Sign Up');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'invalid-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'safe-pass-123');
    final submit = find.widgetWithText(FilledButton, 'Create Account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('sign up explains the minimum password length', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    final toggle = find.text('Don\'t have an account? Sign Up');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '12345');
    final submit = find.widgetWithText(FilledButton, 'Create Account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('Google sign-in is available from the auth screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));

    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
