import 'package:flutter/material.dart';
import 'simple_test_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple iOS Engine Test',
      theme: ThemeData.dark(),
      home: SimpleTestPage(),
    );
  }
}
