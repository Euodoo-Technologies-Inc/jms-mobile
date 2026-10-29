import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/constants/variables.dart';
import 'package:fms/core/theme/app_theme.dart';
import 'package:fms/data/models/traxroot_object_model.dart';
import 'package:fms/page/vehicles/controller/vehicles_controller.dart';
import 'package:fms/page/vehicles/presentation/vehicles_page.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No Traxroot for the company, so loadData clears the list without a
/// network call.
Future<VehiclesController> _pumpVehicles(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({Variables.prefHasTraxroot: false});
  await tester.pumpWidget(GetMaterialApp(
    theme: AppTheme.light(),
    home: const Scaffold(body: VehiclesPage()),
  ));
  await tester.pumpAndSettle();
  return Get.find<VehiclesController>();
}

void main() {
  tearDown(Get.reset);

  testWidgets('no vehicles: empty state, no Retry', (tester) async {
    await _pumpVehicles(tester);
    expect(find.text('No vehicles yet.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('search with no match says so', (tester) async {
    final ctrl = await _pumpVehicles(tester);
    ctrl.objects.add(const TraxrootObjectModel(
        main: TraxrootObjectMain(id: 1, name: 'ORM-2W-01')));
    await tester.pump();
    expect(find.text('ORM-2W-01'), findsOneWidget);

    ctrl.updateQuery('zzz');
    await tester.pump();
    expect(find.text('No vehicles match your search.'), findsOneWidget);
  });

  testWidgets('failed load: error with Retry', (tester) async {
    final ctrl = await _pumpVehicles(tester);
    ctrl.loadFailed.value = true;
    await tester.pump();
    expect(find.text("Couldn't load vehicles."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
