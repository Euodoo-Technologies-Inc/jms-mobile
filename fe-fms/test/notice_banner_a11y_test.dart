import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/widgets/app_feedback.dart';
import 'package:fms/page/dispatch/service/dispatch_notice_service.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('AppFeedback shows a live-region banner with a 48dp close',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final notices = Get.put(DispatchNoticeController());
    addTearDown(Get.reset);

    // Same mount point as main.dart: the builder, above the Navigator.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => DispatchNoticeHost(child: child!),
      home: const Scaffold(),
    ));
    AppFeedback.error('Couldn\'t open maps. Try again.');
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t open maps. Try again.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(notices.current.value, isNull);
    semantics.dispose();
  });
}
