import 'dart:async';

import 'package:flutter/material.dart';
import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/features/home/presentation/pages/home_page.dart';
import 'package:newjuststock/features/legal/presentation/pages/terms_conditions_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/referral_link_service.dart';
import 'package:newjuststock/services/session_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralController = TextEditingController();
  StreamSubscription<String>? _referralSubscription;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillReferralCode();
    _referralSubscription = ReferralLinkService.onReferralCode.listen((code) {
      if (!mounted) return;
      if (_referralController.text.trim().isNotEmpty) return;
      final normalized = code.trim().toUpperCase();
      if (normalized.isEmpty) return;
      _referralController.text = normalized;
    });
  }

  Future<void> _prefillReferralCode() async {
    final code = await ReferralLinkService.getPendingReferralCode();
    if (!mounted) return;
    if (code == null || code.trim().isEmpty) return;
    if (_referralController.text.trim().isNotEmpty) return;
    _referralController.text = code.trim().toUpperCase();
  }

  @override
  void dispose() {
    _referralSubscription?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    FocusScope.of(context).unfocus();

    final referral = _referralController.text.trim();
    final response = await AuthService.signup(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
      referralCode: referral.isEmpty ? null : referral.toUpperCase(),
    );

    if (!mounted) return;

    if (response.ok && response.data != null) {
      final session = response.data!;
      await SessionService.saveSession(session);
      await ReferralLinkService.clearPendingReferralCode();
      if (!mounted) return;
      final Widget target = session.termsAccepted
          ? HomePage(session: session)
          : TermsConditionsPage(session: session);
      Navigator.of(
        context,
      ).pushAndRemoveUntil(fadeRoute(target), (route) => false);
      return;
    }

    setState(() {
      _submitting = false;
      _error = response.message.isNotEmpty
          ? response.message
          : 'Sign up failed. Please try again.';
    });
  }

  void _openLogin() {
    if (_submitting) return;
    Navigator.of(context).pushReplacement(fadeRoute(const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    const darkRed = Color(0xFF7F0000);
    const darkerRed = Color(0xFF8B0000);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              color: Colors.white.withOpacity(0.95),
              elevation: 10,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 54,
                          color: darkerRed,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Create your JustStock account',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Track trades, invite your network, and earn together.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                      const SizedBox(height: 28),

                      // Input Fields
                      _buildTextField(
                        controller: _nameController,
                        icon: Icons.person_outline,
                        label: 'Full name',
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _emailController,
                        icon: Icons.email_outlined,
                        label: 'Email',
                        inputType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _passwordController,
                        icon: Icons.lock_outline,
                        label: 'Password',
                        obscure: true,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _confirmPasswordController,
                        icon: Icons.lock_person_outlined,
                        label: 'Confirm password',
                        obscure: true,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _referralController,
                        icon: Icons.card_giftcard_outlined,
                        label: 'Referral code (optional)',
                      ),
                      const SizedBox(height: 24),

                      // Error message
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                      // Create Account Button
                      ElevatedButton(
                        onPressed: _submitting ? null : _handleSignup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: darkerRed,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          shadowColor: Colors.black38,
                          elevation: 4,
                          foregroundColor: Colors.white,
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Create account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),

                      const SizedBox(height: 20),

                      // Sign In Text
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account? ',
                            style: TextStyle(color: Colors.black87),
                          ),
                          GestureDetector(
                            onTap: _openLogin,
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                color: darkerRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    bool obscure = false,
    TextInputType? inputType,
  }) {
    const darkRed = Color(0xFF7F0000);
    const darkerRed = Color(0xFF8B0000);
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: inputType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.black54),
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFFFFCF3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkerRed, width: 1.5),
        ),
      ),
    );
  }
}
