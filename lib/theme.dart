import 'package:flutter/material.dart';

import 'models/workout.dart';

const brandSeed = Color(0xFFB33F0B);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: brandSeed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    chipTheme: const ChipThemeData(showCheckmark: false),
  );
}

/// Cores por tipo de treino (fundo do ícone e texto), com contraste nos dois temas.
(Color, Color) kindColors(BuildContext context, WorkoutKind k) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (k) {
    case WorkoutKind.corrida:
      return dark ? (const Color(0xFF5C2408), const Color(0xFFFFDBCC)) : (const Color(0xFFFFE0D1), const Color(0xFF8A3008));
    case WorkoutKind.caminhada:
      return dark ? (const Color(0xFF1B4D2E), const Color(0xFFC8F0D4)) : (const Color(0xFFDDF3E4), const Color(0xFF1B5E33));
    case WorkoutKind.bike:
      return dark ? (const Color(0xFF26346E), const Color(0xFFDCE2FF)) : (const Color(0xFFE0E7FF), const Color(0xFF2B3F99));
    case WorkoutKind.academia:
      return dark ? (const Color(0xFF4A2470), const Color(0xFFF1DBFF)) : (const Color(0xFFF1E4FA), const Color(0xFF5B2A86));
    case WorkoutKind.outro:
      return dark ? (const Color(0xFF3A3A3A), const Color(0xFFE6E6E6)) : (const Color(0xFFEEEEEE), const Color(0xFF3E3E3E));
  }
}

IconData kindIcon(WorkoutKind k) {
  switch (k) {
    case WorkoutKind.corrida:
      return Icons.directions_run;
    case WorkoutKind.caminhada:
      return Icons.directions_walk;
    case WorkoutKind.bike:
      return Icons.directions_bike;
    case WorkoutKind.academia:
      return Icons.fitness_center;
    case WorkoutKind.outro:
      return Icons.sports;
  }
}
