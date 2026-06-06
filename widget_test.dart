import 'package:flutter_test/flutter_test.dart';
import 'package:flangapp_app/main.dart';

void main() {
  testWidgets('WebApp builds without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WebApp());
    expect(find.byType(WebApp), findsOneWidget);
  });
}
