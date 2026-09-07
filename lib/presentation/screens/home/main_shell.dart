import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/locale_provider.dart';
import 'chat_list_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

// این provider رو اضافه کن تا از هر جا بشه تب رو عوض کرد
final shellIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final index = ref.watch(shellIndexProvider);

    final pages = [
      const ChatListScreen(),
      const SearchScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(shellIndexProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: isFa ? 'چت‌ها' : 'Chats',
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            selectedIcon: const Icon(Icons.search),
            label: isFa ? 'جستجو' : 'Search',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: isFa ? 'تنظیمات' : 'Settings',
          ),
        ],
      ),
    );
  }
}