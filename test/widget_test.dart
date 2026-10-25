import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rig_car/main.dart';

void main() {
  testWidgets('renders the fleet dashboard', (tester) async {
    await tester.pumpWidget(const RigCarApp());

    expect(find.text('RIG-CAR'), findsOneWidget);
    expect(find.text('Good morning, Alex'), findsOneWidget);
    expect(find.text('Fleet overview'), findsOneWidget);
    expect(find.text('Ranger XLT'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('filters vehicles by category', (tester) async {
    await tester.pumpWidget(const RigCarApp());

    await tester.scrollUntilVisible(
      find.text('SUV'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('SUV'));
    await tester.pumpAndSettle();

    expect(find.text('Model Y Long Range'), findsOneWidget);
    expect(find.text('Bronco Outer Banks'), findsOneWidget);
    expect(find.text('Ranger XLT'), findsNothing);
    expect(find.text('Civic Touring'), findsNothing);
  });
}
