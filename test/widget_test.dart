import 'package:flutter_test/flutter_test.dart';
import 'package:schoolpro/main.dart';

void main() {
  testWidgets('SchoolPro app displays its title', (tester) async {
    await tester.pumpWidget(const SchoolProApp());

    expect(find.text('SchoolPro'), findsOneWidget);
    expect(find.text('School Management System'), findsOneWidget);
  });
}
