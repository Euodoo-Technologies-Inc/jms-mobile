import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fms/page/auth/controller/auth_controller.dart';
import '../widget/auth_button.dart';
import '../widget/auth_text_field.dart';
import 'forgot_password_page.dart';
import 'login_chooser_page.dart';

/// Page for user login.
///
/// Displays a form for email and password entry, handles login validation,
/// and provides navigation to the forgot password page.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final authController = Get.find<AuthController>();
      await authController.loginWithCredentials(
        email: _emailController.text,
        password: _passwordController.text,
        context: context,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
        // Always show a back-to-chooser arrow regardless of nav stack state.
        // On a logout-triggered `Get.offAll(LoginPage)` this page is the root,
        // so the default automatically-implied back button is hidden — that's
        // why we route explicitly via Get.offAll rather than Navigator.pop.
        leading: IconButton(
          tooltip: 'Back to sign-in chooser',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              Get.offAll(() => const LoginChooserPage()),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  // Logo and Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 85,
                          height: 80,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Welcome',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to E-FMS',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Email Field
                  AuthTextField(
                    label: 'Email',
                    hint: 'Fill your email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(value)) {
                        return 'Invalid email address';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // Password Field
                  AuthTextField(
                    label: 'Password',
                    hint: 'Fill your password',
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: theme.colorScheme.primary,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: _togglePasswordVisibility,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 4) {
                        return 'Password must be at least 4 characters long';
                      }
                      // if (!RegExp(
                      //   r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~]).{8,}$',
                      // ).hasMatch(value)) {
                      //   return 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character';
                      // }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordPage(),
                          ),
                        );
                      },
                      child: Text(
                        'Forgot Password',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Register Button
                  AuthButton(
                    text: 'Login',
                    onPressed: _handleLogin,
                    isLoading: _isLoading,
                    isOutlined: true,
                  ),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
