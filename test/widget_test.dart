import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolpro/main.dart';

void main() {
  testWidgets('SchoolPro authentication screen displays its title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(urdu: false, onLanguageChanged: (_) {})),
    );

    expect(find.text('SchoolPro'), findsOneWidget);
    expect(find.text('School Management System'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
