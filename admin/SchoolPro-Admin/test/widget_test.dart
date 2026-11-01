import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolpro_admin_web/main.dart';

void main() {
  testWidgets('Admin access gate displays denial without an admin claim', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AccessDeniedScreen()));
    expect(find.text('Admin Access Denied'), findsOneWidget);
  });
}
