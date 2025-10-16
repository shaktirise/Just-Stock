import 'package:flutter/material.dart';

import 'package:newjuststock/app/app.dart';
import 'package:newjuststock/services/referral_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReferralLinkService.initialize();
  runApp(const MyApp());
}
