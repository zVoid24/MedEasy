import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isRegister = false;
  final _usernameCtrl = TextEditingController();
  final _pharmacyNameCtrl = TextEditingController();
  final _pharmacyLocationCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _pharmacyNameCtrl.dispose();
    _pharmacyLocationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    if (_isRegister) {
      await auth.registerOwner(
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        pharmacyName: _pharmacyNameCtrl.text.trim(),
        pharmacyLocation: _pharmacyLocationCtrl.text.trim(),
      );
    } else {
      await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
    }
    if (auth.isAuthenticated && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else if (auth.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isRegister ? 'Register Owner' : 'Login',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_isRegister)
                      TextFormField(
                        controller: _usernameCtrl,
                        decoration: const InputDecoration(labelText: 'Owner name'),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pharmacyNameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Pharmacy name'),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pharmacyLocationCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Pharmacy location (city)'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: auth.loading ? null : _submit,
                      child: Text(auth.loading
                          ? 'Please wait...'
                          : (_isRegister ? 'Register & start' : 'Login')),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isRegister = !_isRegister;
                        });
                      },
                      child: Text(_isRegister
                          ? 'Have an account? Login'
                          : 'Create owner account'),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
