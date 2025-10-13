import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/signup_page.dart';
import 'package:newjuststock/features/home/presentation/pages/home_page.dart';
import 'package:newjuststock/features/legal/presentation/pages/terms_conditions_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/session_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    FocusScope.of(context).unfocus();

    final response = await AuthService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (response.ok && response.data != null) {
      final session = response.data!;
      await SessionService.saveSession(session);
      if (!mounted) return;
      final Widget target = session.termsAccepted
          ? HomePage(session: session)
          : TermsConditionsPage(session: session);
      Navigator.of(context).pushAndRemoveUntil(fadeRoute(target), (r) => false);
      return;
    }

    setState(() {
      _submitting = false;
      _error = response.message.isNotEmpty
          ? response.message
          : 'Sign in failed. Please try again.';
    });
  }

  void _openSignup() {
    if (_submitting) return;
    Navigator.of(context).pushReplacement(fadeRoute(const SignupPage()));
  }

  void _showForgotPasswordSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Password reset coming soon.')),
      );
  }

  String? _validateEmail(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter your email address.';
    final emailPattern = RegExp(
      r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
      caseSensitive: false,
    );
    if (!emailPattern.hasMatch(input)) return 'Enter a valid email.';
    return null;
  }

  String? _validatePassword(String? value) {
    final input = value ?? '';
    if (input.isEmpty) return 'Enter your password.';
    if (input.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFFF8E7);
    const yellow = Color(0xFFFFD500);
    const darkOrange = Color(0xFFE67E22);

    return Scaffold(
      backgroundColor: cream,
      body: Stack(
        children: [
          // 🔶 Curved Header with Highlighted "JustStock"
          SizedBox(
            height: 260,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipPath(
                  clipper: _CurvedHeaderClipper(),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFFC300), // yellow
                          Color(0xFFFFA000), // amber
                          Color(0xFFE67E22), // orange
                        ],
                      ),
                    ),
                  ),
                ),
                // Centered JustStock Branding
                const Positioned(
                  bottom: 90,
                  child: Text(
                    'JustStock',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 40,
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(
                          color: Colors.black38,
                          offset: Offset(2, 3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 🧾 Card Body
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 10,
                  shadowColor: Colors.black26,
                  color: Colors.white.withOpacity(0.97),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 48, color: darkOrange),
                          const SizedBox(height: 16),
                          const Text(
                            'Welcome back!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sign in with your email and password to continue.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Email
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: _validateEmail,
                            decoration: _inputDecoration(
                              label: 'Email',
                              icon: Icons.email_outlined,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Password
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            validator: _validatePassword,
                            decoration: _inputDecoration(
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                            ),
                          ),

                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _submitting
                                  ? null
                                  : _showForgotPasswordSnackbar,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text('Forgot password?'),
                            ),
                          ),

                          // Error
                          if (_error != null) ...[
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // Sign In Button
                          ElevatedButton(
                            onPressed: _submitting ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: yellow,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              elevation: 4,
                              shadowColor: Colors.black38,
                              foregroundColor: Colors.black,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.black),
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                          const SizedBox(height: 16),

                          // Create Account
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('New here? ',
                                  style: TextStyle(color: Colors.black87)),
                              TextButton(
                                onPressed: _openSignup,
                                style: TextButton.styleFrom(
                                  foregroundColor: darkOrange,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                child: const Text('Create account'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Custom Input Decoration
  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.black54),
      filled: true,
      fillColor: const Color(0xFFFFFCF3),
      labelStyle: const TextStyle(color: Colors.black87),
      floatingLabelStyle: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.black26),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE67E22), width: 1.5),
      ),
    );
  }
}

// 🌀 Custom Curved Header
class _CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 60);
    path.quadraticBezierTo(
      size.width * 0.5,
      size.height,
      size.width,
      size.height - 60,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
