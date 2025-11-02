import 'package:flutter/material.dart';

import 'package:newjuststock/features/splash/presentation/pages/splash_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
      // Brand palette: Dark Red focused
    // - Primary (dark red): #7F0000
    // - Darker Red (header/accent): #8B0000
    const darkRed = Color(0xFF7F0000);
    const darkerRed = Color(0xFF8B0000);
    return MaterialApp(
      title: 'JustStock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Dark red primary with darker red accents; white surfaces
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: darkRed,
              brightness: Brightness.light,
            ).copyWith(
              primary: darkRed,
              secondary: darkerRed,
              background: Colors.white,
              surface: Colors.white,
            ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkerRed,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // White background for contrast with dark red elements
        scaffoldBackgroundColor: Colors.white,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: darkRed, width: 2),
          ),
          floatingLabelStyle: TextStyle(color: darkerRed),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(darkRed),
            foregroundColor: const MaterialStatePropertyAll(Colors.white),
          ),
        ),
      ),
      home: const SplashPage(),
    );
  }
}
