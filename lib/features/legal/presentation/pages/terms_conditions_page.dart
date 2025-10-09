import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/features/home/presentation/pages/home_page.dart';
import 'package:newjuststock/services/session_service.dart';

class TermsConditionsPage extends StatefulWidget {
  final AuthSession session;

  const TermsConditionsPage({super.key, required this.session});

  @override
  State<TermsConditionsPage> createState() => _TermsConditionsPageState();
}

class _TermsConditionsPageState extends State<TermsConditionsPage> {
  static const _brandSecondary = Color(0xFFF7971E);
  static const _textPrimary = Color(0xFF3B2E0A);
  static const _textSecondary = Color(0xFF5A4730);

  bool _submitting = false;

  Future<void> _handleAccept() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final updatedSession = widget.session.copyWith(termsAccepted: true);
    final accessToken = updatedSession.accessToken.trim();
    if (accessToken.isEmpty) {
      await SessionService.clearSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        fadeRoute(const LoginPage()),
        (route) => false,
      );
      return;
    }
    await SessionService.saveSession(updatedSession);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(
        HomePage(
          session: updatedSession,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _handleExit() async {
    if (_submitting) return;
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final headlineStyle = textTheme.titleLarge?.copyWith(
      color: _textPrimary,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );
    final bodyStyle = textTheme.bodyMedium?.copyWith(
      color: _textSecondary,
      height: 1.45,
    );

    const bullets = [
      'Any available service, including but not limited to the compliance status and screening of stocks, is purely for information and educational purposes.',
      'We do not undertake any liability for damage, cost, harm, or loss caused in connection with the information available in the app, website, or blogs.',
      'Be aware of the risks involved in trading in financial markets. We recommend consulting a qualified financial advisor before making any investment or financial decision.',
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF5C6),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFDD978), Color(0xFFFFF7DD)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 28,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(26, 28, 26, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Disclaimer', style: headlineStyle),
                        const SizedBox(height: 12),
                        Text(
                          'We are not a registered broker, investment advisor, financial advisor, or any license required financial institution.',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: 18),
                        ...bullets.map(
                          (point) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: const BoxDecoration(
                                    color: _brandSecondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(point, style: bodyStyle)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _PrimaryButton(
                          label: 'Accept',
                          gradient: const [
                            Color(0xFFFFD200),
                            Color(0xFFF7971E),
                          ],
                          onTap: _submitting ? null : _handleAccept,
                          busy: _submitting,
                          textColor: Colors.white,
                        ),
                        const SizedBox(height: 14),
                        _PrimaryButton(
                          label: 'Exit',
                          gradient: const [
                            Color(0xFF1F1F1F),
                            Color(0xFF1F1F1F),
                          ],
                          onTap: _submitting ? null : _handleExit,
                          textColor: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final List<Color> gradient;
  final VoidCallback? onTap;
  final bool busy;
  final Color textColor;

  const _PrimaryButton({
    required this.label,
    required this.gradient,
    required this.onTap,
    required this.textColor,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.65,
      child: SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: onTap,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(textColor),
                        ),
                      )
                    : Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
