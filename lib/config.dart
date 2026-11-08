import 'package:firebase_core/firebase_core.dart';

/// Configuração do build, lida de config/app.json:
///   flutter run --dart-define-from-file=config/app.json
///
/// Nada aqui é segredo: a chave de API do Firebase identifica o projeto e é
/// protegida pelas regras do Firestore e pelo pacote/SHA-1 do app.
class AppConfig {
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// ID do cliente OAuth *web* (Firebase → Authentication → Google → Configuração do SDK da Web).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static const privacyUrl =
      String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://fast-run-plano.onrender.com/privacidade');
  static const deleteAccountUrl =
      String.fromEnvironment('DELETE_ACCOUNT_URL', defaultValue: 'https://fast-run-plano.onrender.com/excluir-conta');

  /// Sem Firebase configurado, o app roda sem login e sem nuvem (modo local).
  static bool get firebaseEnabled => firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseProjectId.isNotEmpty;

  static FirebaseOptions get firebaseOptions => const FirebaseOptions(
        apiKey: firebaseApiKey,
        appId: firebaseAppId,
        projectId: firebaseProjectId,
        messagingSenderId: firebaseSenderId,
        storageBucket: firebaseStorageBucket,
      );
}
