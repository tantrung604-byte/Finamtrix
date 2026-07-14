import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive.dart';
import 'home_screen.dart';
import 'macro_screen.dart';
import 'micro_screen.dart';
import 'ai_cmo_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // Let's create a callback function to switch screen index from child widgets (e.g. quick stats)
  void _switchTab(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Screens list mapping 5 tabs
    final List<Widget> screens = [
      HomeScreen(onNavigateToTab: _switchTab),
      MacroScreen(),
      MicroScreen(),
      AiCmoScreen(),
      ProfileScreen(),
    ];

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
        child: IndexedStack(
          sizing: StackFit.expand,
          index: _currentIndex,
          children: screens,
        ),
      ),
    );

    // Desktop / large web: side NavigationRail (better UX than a bottom bar).
    if (context.isDesktop) {
      return Scaffold(
        body: SafeArea(
          top: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _currentIndex,
                onDestinationSelected: _switchTab,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white.withOpacity(0.03),
                indicatorColor: Colors.white.withOpacity(0.10),
                selectedLabelTextStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                unselectedLabelTextStyle:
                    TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6)),
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('💹',
                      style: TextStyle(fontSize: 26), textAlign: TextAlign.center),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('Trang chủ'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.show_chart_outlined),
                    selectedIcon: Icon(Icons.show_chart),
                    label: Text('Vĩ Mô'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.business_center_outlined),
                    selectedIcon: Icon(Icons.business_center),
                    label: Text('Vi Mô'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: Text('AI CMO'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: Text('Tài khoản'),
                  ),
                ],
              ),
              VerticalDivider(
                  width: 1, thickness: 1, color: Colors.white.withOpacity(0.06)),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    // Phone / tablet: bottom navigation (mobile-first).
    return Scaffold(
      body: SafeArea(
        top: false, // Let screens handle their own top safearea if needed
        child: content,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.06),
              width: 1.0,
            ),
          ),
        ),
        child: ResponsiveShell(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _switchTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Trang chủ',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart_outlined),
                selectedIcon: Icon(Icons.show_chart),
                label: 'Vĩ Mô',
              ),
              NavigationDestination(
                icon: Icon(Icons.business_center_outlined),
                selectedIcon: Icon(Icons.business_center),
                label: 'Vi Mô',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'AI CMO',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Tài khoản',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
