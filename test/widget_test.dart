import 'package:flutter_test/flutter_test.dart';

import 'package:rig_car/main.dart';

void main() {
  testWidgets('renders the Godot rigging workbench', (tester) async {
    await tester.pumpWidget(const RigCarApp());

    expect(find.text('RIG-CAR'), findsOneWidget);
    expect(find.text('3D VIEWPORT'), findsOneWidget);
    expect(find.text('Vehicle model'), findsOneWidget);
    expect(find.text('Choose model'), findsOneWidget);
  });

  testWidgets('switches workflow panels and updates physics', (tester) async {
    await tester.pumpWidget(const RigCarApp());

    await tester.tap(find.text('3  Tune physics'));
    await tester.pumpAndSettle();
    expect(find.text('Vehicle physics'), findsOneWidget);
    expect(find.text('Mass'), findsOneWidget);

    await tester.tap(find.text('2  Rig wheels'));
    await tester.pumpAndSettle();
    expect(find.text('Wheel nodes'), findsOneWidget);
    expect(find.text('AWD'), findsOneWidget);
  });

  testWidgets('shows the export panel', (tester) async {
    await tester.pumpWidget(const RigCarApp());

    await tester.tap(find.text('4  Export to Godot'));
    await tester.pumpAndSettle();

    expect(find.text('Godot package'), findsOneWidget);
    expect(find.text('rig_car.tscn'), findsOneWidget);
    expect(find.text('Download Godot files'), findsOneWidget);
  });
}
