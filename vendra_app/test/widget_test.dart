// Basic widget test for Vendra app
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_app/main.dart';

void main() {
  testWidgets('Vendra app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const VendraApp());
    expect(find.text('Vendra'), findsWidgets);
  });
}
