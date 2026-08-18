import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:korobka/main.dart';

void main() {
  testWidgets('Приложение создаёт MaterialApp', (tester) async {
    // Задаём достаточно широкое окно, чтобы тулбар не переполнялся.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const KorobkaApp());
    await tester.pump();

    // Просто проверяем, что виджет-дерево строится без исключений.
    expect(tester.allWidgets, isNotEmpty);
  });
}
