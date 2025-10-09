import 'package:flutter/material.dart';

import 'package:newjuststock/features/splash/presentation/pages/splash_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Brand palette: Yellow focused
    // - Primary (bright): #FFD200
    // - Dark Yellow (header/accent): #F7971E
    const brandYellow = Color(0xFFFFD200);
    const brandYellowDark = Color(0xFFF7971E);
    return MaterialApp(
      title: 'JustStock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Yellow primary with darker yellow accents; white surfaces
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: brandYellow,
              brightness: Brightness.light,
            ).copyWith(
              primary: brandYellow,
              secondary: brandYellowDark,
              background: Colors.white,
              surface: Colors.white,
            ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: brandYellowDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // Subtle light background so symbol images pop
        scaffoldBackgroundColor: Colors.white,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: brandYellow, width: 2),
          ),
          floatingLabelStyle: TextStyle(color: brandYellowDark),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(brandYellow),
            foregroundColor: const MaterialStatePropertyAll(Colors.white),
          ),
        ),
      ),
      home: const SplashPage(),
    );
  }
}
