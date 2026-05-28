import 'package:app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows app title', (tester) async {
    await tester.pumpWidget(const SnuMealsApp());

    final app = tester.widget<SnuMealsApp>(find.byType(SnuMealsApp));
    expect(app, isA<SnuMealsApp>());
  });
}
