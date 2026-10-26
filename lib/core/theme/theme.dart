import 'package:flutter/material.dart';

ThemeData lightMode = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.light(
    brightness: Brightness.light,
    surface: Colors.white,
    primary: Color(0xFF2073A9),
    secondary: Color(0xFFf3c404),
    tertiary: Colors.indigo[900],
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    toolbarHeight: kToolbarHeight,
  ),
);

ThemeData darkMode = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.dark(
    brightness: Brightness.dark,
    surface: Colors.grey.shade900,
    primary: Color(0xFF2073A9),
    secondary: Color(0xFFf3c404),
    tertiary: Colors.deepPurple,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    toolbarHeight: kToolbarHeight,
  ),
);

extension ModeChangerText on ColorScheme {
  String get modeChangerText {
    return brightness == Brightness.dark ? "Light Mode" : "Dark Mode";
  }

  Color get fontPrimary {
    return brightness == Brightness.dark ? Colors.black : Colors.white;
  }

  Color get fontInverted {
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }

  Color get fontSecondary {
    return brightness == Brightness.dark ? Colors.grey : Colors.black87;
  }

  Color get cardPrimary {
    return brightness == Brightness.dark ? Color(0xFFCFCFCD) : Colors.white;
  }

  Color get cardSecondary {
    return brightness == Brightness.dark ? Color(0xFF2073A9) : Colors.white;
  }

  Color get greyCard {
    return brightness == Brightness.dark
        ? Color(0xFFCFCFCD)
        : Color(0xEECFCFCD);
  }
}

extension GradientScheme on ColorScheme {
  // Home-only corrections preserve the other tabs' established presentation.
  Color get homeCard =>
      brightness == Brightness.dark ? const Color(0xFF2C2C2C) : cardPrimary;

  Color get homeAccent =>
      brightness == Brightness.dark ? const Color(0xFF8DCDF4) : primary;

  LinearGradient get homeGradient => brightness == Brightness.dark
      ? const LinearGradient(
          colors: [Color(0xFF2073A9), Color(0xFF145678)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : primaryGradient;

  LinearGradient get primaryGradient {
    return brightness == Brightness.dark
        ? LinearGradient(
            colors: [Color(0xFF2073A9), Colors.deepPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [Color(0xFF2073A9), Color(0xFF13BDFA)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          );
  }

  LinearGradient get backgroundGradient {
    return brightness == Brightness.dark
        ? LinearGradient(
            colors: [Color.fromARGB(255, 248, 248, 232), Color(0xFFE1E1E1)],
          )
        : LinearGradient(
            colors: [Color.fromARGB(255, 245, 237, 226), Colors.white],
          );
  }
}
