import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const DeceptaApp());
}

class DeceptaApp extends StatelessWidget {
  const DeceptaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Decepta AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.greenAccent,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Dark Blue
      ),
      home: const HomeScreen(),
    );
  }
}
