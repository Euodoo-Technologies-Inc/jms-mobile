import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/page/home/presentation/home_page.dart';
import 'package:fms/page/vehicles/presentation/vehicles_page.dart';
import 'package:fms/page/jobs/presentation/jobs_gate_tab.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:fms/core/navigation/navigation_controller.dart';
import 'core/widgets/app_bar_widget.dart';
import 'package:fms/core/services/subscription.dart';

class NavBar extends StatefulWidget {
  const NavBar({super.key});

  @override
  State<NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  late final NavigationController navController;

  @override
  void initState() {
    super.initState();
    navController = Get.put(NavigationController());
    _configureTabs();
  }

  void _configureTabs() {
    final isPro = subscriptionService.currentPlan == Plan.pro;
    final authController = Get.find<AuthController>();
    final role = authController.userRole.value;
    navController.configureTabs(isPro: isPro, role: role);
  }

  Widget _widgetForTitle(String title) {
    switch (title) {
      case 'Dashboard':
        return const HomeTab();
      case 'Vehicles':
        return const VehiclesPage();
      case 'Jobs':
        return const JobsGateTab();
      default:
        return const SizedBox.shrink();
    }
  }

  NavigationDestination _destinationForTitle(String title) {
    switch (title) {
      case 'Dashboard':
        return const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        );
      case 'Vehicles':
        return const NavigationDestination(
          icon: Icon(Icons.directions_car_outlined),
          selectedIcon: Icon(Icons.directions_car),
          label: 'Vehicles',
        );
      case 'Jobs':
        return const NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'Jobs',
        );
      default:
        return NavigationDestination(
          icon: const Icon(Icons.help_outline),
          selectedIcon: const Icon(Icons.help),
          label: title,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        if (navController.selectedIndex.value != 0) {
          navController.changeTab(0);
        } else {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Exit App'),
              content: const Text('Do you want to exit the application?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Exit'),
                ),
              ],
            ),
          );

          if (shouldExit == true && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Obx(
        () {
          final titles = navController.titles;
          final tabs = titles.map((t) => _widgetForTitle(t)).toList();
          final destinations = titles.map((t) => _destinationForTitle(t)).toList();

          return Scaffold(
            appBar: AppBarWidget(title: navController.currentTitle),
            body: IndexedStack(
              index: navController.selectedIndex.value,
              children: tabs,
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: navController.selectedIndex.value,
              onDestinationSelected: navController.changeTab,
              destinations: destinations,
            ),
          );
        },
      ),
    );
  }
}
