import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:fms/page/home/presentation/home_page.dart';
import 'package:fms/page/vehicles/presentation/vehicles_page.dart';
import 'package:fms/page/jobs/presentation/jobs_gate_tab.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import 'package:fms/core/navigation/navigation_controller.dart';
import 'core/widgets/app_bar_widget.dart';
import 'package:fms/core/widgets/app_dialog.dart';
import 'package:fms/core/services/subscription.dart';
import 'package:fms/core/theme/dispatch_palette.dart';

class NavBar extends StatefulWidget {
  const NavBar({super.key});

  @override
  State<NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  late final NavigationController navController;
  late final Worker _roleWorker;

  @override
  void initState() {
    super.initState();
    navController = Get.put(NavigationController());
    _configureTabs();
    final authController = Get.find<AuthController>();
    _roleWorker = ever(authController.userRole, (_) => _configureTabs());
  }

  @override
  void dispose() {
    _roleWorker.dispose();
    super.dispose();
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
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (navController.selectedIndex.value != 0) {
          navController.changeTab(0);
        } else {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AppDialog(
              icon: Icons.exit_to_app,
              accent: DispatchColors.danger,
              title: 'Exit app?',
              message: 'Are you sure you want to close the application?',
              actions: [
                AppDialogButton(
                  label: 'Stay',
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                AppDialogButton(
                  label: 'Exit',
                  filled: true,
                  color: DispatchColors.danger,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          );

          // Actually close the app (background it on Android). A plain
          // Navigator.pop here would empty the root navigator and leave a
          // black screen instead of exiting.
          if (shouldExit == true) {
            await SystemNavigator.pop();
          }
        }
      },
      child: Obx(
        () {
          final titles = navController.titles;
          final tabs = titles.map((t) => _widgetForTitle(t)).toList();
          final destinations = titles.map((t) => _destinationForTitle(t)).toList();

          final palette = context.dispatch;
          return Scaffold(
            appBar: AppBarWidget(title: navController.currentTitle),
            body: IndexedStack(
              index: navController.selectedIndex.value,
              children: tabs,
            ),
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.pageSurface,
                border: Border(top: BorderSide(color: palette.cardBorder)),
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  indicatorColor:
                      DispatchColors.brand.withValues(alpha: 0.14),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? DispatchColors.brand : palette.subtle,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      size: 22,
                      color: selected ? DispatchColors.brand : palette.subtle,
                    );
                  }),
                ),
                child: NavigationBar(
                  height: 60,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: navController.selectedIndex.value,
                  onDestinationSelected: navController.changeTab,
                  destinations: destinations,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
