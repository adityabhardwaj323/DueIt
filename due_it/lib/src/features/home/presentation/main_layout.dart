import 'package:flutter/material.dart';

import 'smart_inbox_screen.dart';
import '../../notes/presentation/notes_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';
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
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.inbox), label: 'Inbox'),
          BottomNavigationBarItem(icon: Icon(Icons.note), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.check_box), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: 'Dues'),
        ],
      ),
    );
  }
}
