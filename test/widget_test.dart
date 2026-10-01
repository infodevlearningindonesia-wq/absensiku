import 'package:flutter/material.dart';

class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absensiku'),
        backgroundColor: Colors.blue,
      ),
      body: const Center(
        child: Text(
            'Hello World',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}