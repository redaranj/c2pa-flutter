// Widget tests for C2PA Flutter example app

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:c2pa_flutter_example/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const C2paExampleApp());

    // Verify that the app renders some expected content
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
