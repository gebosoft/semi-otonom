import 'package:flutter/material.dart';
import 'package:api_client/api.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final health = HealthResponse(status: 'healthy');
    return MaterialApp(
      title: 'semi-otonom',
      home: Scaffold(
        body: Center(child: Text('API: ${health.status}')),
      ),
    );
  }
}
