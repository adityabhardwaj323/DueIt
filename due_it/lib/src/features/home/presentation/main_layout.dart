import 'package:flutter/material.dart';

import 'smart_inbox_screen.dart';
import '../../notes/presentation/notes_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';
import '../../tasks/presentation/habits_screen.dart';
import '../../expenses/presentation/dues_screen.dart';
import '../../../core/notifications/fcm_service.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const SmartInboxScreen(),
    const NotesScreen(),
    const TasksScreen(),
    const HabitsScreen(),
    const DuesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Initialize FCM when the user first successfully lands in the authenticated app
    fcmService.init();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF2B2B36) : const Color(0xFFE9E8EE),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          elevation: 0,
          backgroundColor: theme.cardColor,
          indicatorColor: theme.colorScheme.primary.withOpacity(0.16),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.sticky_note_2_outlined),
              selectedIcon: Icon(Icons.sticky_note_2_rounded),
              label: 'Notes',
            ),
            NavigationDestination(
              icon: Icon(Icons.check_circle_outline_rounded),
              selectedIcon: Icon(Icons.check_circle_rounded),
              label: 'Tasks',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_fire_department_outlined),
              selectedIcon: Icon(Icons.local_fire_department_rounded),
              label: 'Habits',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Dues',
            ),
          ],
        ),
      ),
    );
  }
}
