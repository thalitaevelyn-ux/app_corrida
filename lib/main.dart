import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const AppCorrida()));
}

class AppCorrida extends StatelessWidget {
  const AppCorrida({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Corrida',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.goal == null || s.plan == null) return const OnboardingScreen();
    return const Shell();
  }
}
