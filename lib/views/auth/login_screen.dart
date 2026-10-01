import 'package:absensiku/views/users/home_screen.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();  

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }   
// Loading indicator
void _showLoading() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(),
    ),
  );
} 
// Redirect ke Home Screen
void _handleLoginSuccess() {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (context) => const HomeScreen()),
  );
} 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Screen'),
        backgroundColor: Colors.blue,
      ),  
      body:   Column(
        children: [
        // form
        TextFormField(
          controller: _emailController,
          key: _formKey,
          decoration: const InputDecoration(
            labelText: "Email",
          ),
        ),  
        TextFormField(
          controller: _passwordController,
          key: _formKey,
          decoration: const InputDecoration(
            labelText: "Password",
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            _handleLoginSuccess();
            _showLoading();
          },
          child: const Text("Login"),
        ),  
      ],
    )
  );
}
}
