import 'package:flutter_test/flutter_test.dart';

import 'package:geoseize/main.dart';

void main() {
  testWidgets('GeoSeizeApp loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const GeoSeizeApp());

    // Verify that MapScreen loads (e.g. looking for the app bar title)
    expect(find.text('GeoSeize'), findsOneWidget);
  });
}
