import 'package:flutter_test/flutter_test.dart';

import 'package:korobka/main.dart';

void main() {
  testWidgets('Приложение создаёт MaterialApp', (tester) async {
    await tester.pumpWidget(const KorobkaApp());

    // Просто проверяем, что виджет-дерево строится без исключений.
    expect(tester.allWidgets, isNotEmpty);
  });
}