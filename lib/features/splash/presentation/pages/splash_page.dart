// Removed direct math usage; animations handled by JustStockLoader.

import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/features/home/presentation/pages/home_page.dart';
import 'package:newjuststock/features/legal/presentation/pages/terms_conditions_page.dart';
import 'package:newjuststock/services/session_service.dart';
import 'package:newjuststock/widgets/juststock_loader.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  void _bootstrap() {
    Future.microtask(() async {
      final session = await SessionService.ensureSession();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 5000));
      if (!mounted) return;
      if (session != null && session.isValid) {
        final Widget target = session.termsAccepted
            ? HomePage(session: session)
            : TermsConditionsPage(session: session);
        Navigator.of(context).pushReplacement(fadeRoute(target));
      } else {
        Navigator.of(context)
            .pushReplacement(fadeRoute(const LoginPage()));
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Use the provided banner image as the loader with a gentle pulse
            JustStockLoader(
              size: 240,
              imagePath: 'assets/app_icon/juststock.png',
              showRing: false,
              borderRadius: BorderRadius.circular(16),
            ),
            const SizedBox(height: 18),
            Text(
              'Loading...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                    letterSpacing: 0.3,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
