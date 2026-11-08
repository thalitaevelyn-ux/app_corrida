import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Erro de login com mensagem pronta para o usuário.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Login com Google ou e-mail e senha (Firebase Authentication).
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;
  bool _googleReady = false;

  Stream<User?> get changes => _auth.authStateChanges();
  User? get user => _auth.currentUser;

  /// Token de acesso enviado ao backend (renovado automaticamente pelo Firebase).
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  Future<void> signInWithGoogle() async {
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(serverClientId: AppConfig.googleWebClientId);
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw AuthException('O Google não devolveu a credencial. Tente de novo.');
      await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw AuthException('Login com Google cancelado.');
      }
      debugPrint('Google Sign-In: ${e.code} ${e.description}');
      throw AuthException('Não foi possível entrar com o Google (${e.code.name}).');
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  Future<void> createAccount(String name, String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      await cred.user?.updateDisplayName(name.trim());
      await cred.user?.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  Future<void> signOut() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  static String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou senha incorretos.';
      case 'email-already-in-use':
        return 'Já existe uma conta com este e-mail. Entre com ele ou recupere a senha.';
      case 'weak-password':
        return 'Senha fraca: use pelo menos 8 caracteres.';
      case 'too-many-requests':
        return 'Muitas tentativas. Espere alguns minutos e tente de novo.';
      case 'network-request-failed':
        return 'Sem conexão com a internet.';
      case 'account-exists-with-different-credential':
        return 'Este e-mail já está cadastrado com outra forma de login.';
      default:
        return 'Não foi possível entrar (${e.code}).';
    }
  }
}
