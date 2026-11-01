import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolpro/main.dart';

void main() {
  testWidgets('Pending account screen explains the approval gate', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PendingScreen(urdu: false)));
    expect(find.text('Your account is awaiting approval. Contact the school admin.'), findsOneWidget);
  });
}
