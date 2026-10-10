import 'package:flutter_test/flutter_test.dart';
import 'package:cmc_native/main.dart';

void main() {
  testWidgets('CmcNativeApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CmcNativeApp());

    // Verify that CmcNativeApp builds without crashing.
    expect(find.byType(CmcNativeApp), findsOneWidget);
  });
}
