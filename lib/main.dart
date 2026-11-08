import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'services/auth_service.dart';
import 'services/firestore_repo.dart';
import 'services/plan_api.dart';
import 'state/app_state.dart';
import 'theme.dart';

const appVersion = '1.1.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  AuthService? auth;
  if (AppConfig.firebaseEnabled) {
    await Firebase.initializeApp(options: AppConfig.firebaseOptions);
    auth = AuthService();
  }
  runApp(FastRunApp(auth: auth));
}

class FastRunApp extends StatelessWidget {
  const FastRunApp({super.key, this.auth});

  /// null = Firebase não configurado neste build (modo local, sem login).
  final AuthService? auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fast run',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: auth == null
          ? ChangeNotifierProvider(create: (_) => AppState(appVersion: appVersion)..init(), child: const _Home())
          : _AuthGate(auth: auth!),
    );
  }
}

/// Login → aceite da política → app (dados separados por usuário).
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.auth});
  final AuthService auth;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  /// uid → aceite já conferido no Firestore.
  final _accepted = <String, bool>{};

  Future<void> _onSignedIn({required bool acceptedTerms}) async {
    final u = widget.auth.user;
    if (u == null) return;
    final repo = FirestoreRepo(u.uid, email: u.email, name: u.displayName);
    if (acceptedTerms) {
      await repo.createProfile(acceptedTerms: true);
      if (mounted) setState(() => _accepted[u.uid] = true);
    }
  }

  Future<bool> _checkTerms(User u) async {
    if (_accepted[u.uid] == true) return true;
    try {
      final ok = await FirestoreRepo(u.uid).hasAcceptedTerms();
      _accepted[u.uid] = ok;
      return ok;
    } catch (_) {
      return true; // sem rede: não bloqueia quem já usava o app
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: widget.auth.changes,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final u = snap.data;
        if (u == null) return LoginScreen(auth: widget.auth, onSignedIn: _onSignedIn);
        return FutureBuilder<bool>(
          key: ValueKey('terms-${u.uid}-${_accepted[u.uid]}'),
          future: _checkTerms(u),
          builder: (context, t) {
            if (!t.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (!t.data!) {
              return TermsGate(
                onAccept: () async {
                  await FirestoreRepo(u.uid, email: u.email, name: u.displayName).createProfile(acceptedTerms: true);
                  setState(() => _accepted[u.uid] = true);
                },
                onDecline: widget.auth.signOut,
              );
            }
            return MultiProvider(
              key: ValueKey(u.uid),
              providers: [
                Provider<AuthService>.value(value: widget.auth),
                ChangeNotifierProvider(
                  create: (_) => AppState(
                    cloud: FirestoreRepo(u.uid, email: u.email, name: u.displayName),
                    api: PlanApi(idToken: widget.auth.idToken),
                    appVersion: appVersion,
                  )..init(),
                ),
              ],
              child: const _Home(),
            );
          },
        );
      },
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.goal == null || s.plan == null) return const OnboardingScreen();
    return const Shell();
  }
}
