import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'cloud_config.dart';

abstract class AccountIdentity {
  String? get uid;
  String? get email;
  Future<void> initialize();
  Future<void> signIn();
  Future<void> signOut();
  Future<void> deleteAccount();
  Future<String> idToken();
  Future<Map<String, String>> driveHeaders({bool interactive = false});
}

class GoogleAccountIdentity implements AccountIdentity {
  FirebaseAuth? _auth;
  GoogleSignInAccount? _google;
  bool _initialized = false;
  String? _lastDriveToken;
  static const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
  @override
  String? get uid => _auth?.currentUser?.uid;
  @override
  String? get email => _auth?.currentUser?.email;
  @override
  Future<void> initialize() async {
    if (_initialized || !CloudConfig.identityReady) return;
    final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: CloudConfig.apiKey,
        appId: CloudConfig.appId,
        messagingSenderId: CloudConfig.senderId,
        projectId: CloudConfig.projectId,
      ),
    );
    _auth = FirebaseAuth.instanceFor(app: app);
    await GoogleSignIn.instance.initialize(
      serverClientId: CloudConfig.googleClientId,
    );
    _initialized = true;
  }

  @override
  Future<void> signIn() async {
    await initialize();
    if (_auth == null) {
      throw StateError('Google sign-in is not configured in this build.');
    }
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) {
      throw StateError('Google did not return a sign-in token.');
    }
    await _auth!.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
    _google = account;
  }

  @override
  Future<void> signOut() async {
    _google = null;
    _lastDriveToken = null;
    await _auth?.signOut();
    if (_initialized) await GoogleSignIn.instance.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    await _auth?.currentUser?.delete();
    _google = null;
    if (_initialized) await GoogleSignIn.instance.signOut();
  }

  @override
  Future<String> idToken() async {
    final token = await _auth?.currentUser?.getIdToken();
    if (token == null) {
      throw StateError('Sign in to your Google account first.');
    }
    return token;
  }

  @override
  Future<Map<String, String>> driveHeaders({bool interactive = false}) async {
    if (uid == null) throw StateError('Sign in before connecting Drive.');
    _google ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (_google == null && interactive) {
      _google = await GoogleSignIn.instance.authenticate();
    }
    if (_google == null ||
        _google!.email.toLowerCase() != email?.toLowerCase()) {
      _google = null;
      throw StateError('Reconnect the same Google account to use its Drive.');
    }
    if (interactive && _lastDriveToken != null) {
      await _google!.authorizationClient.clearAuthorizationToken(
        accessToken: _lastDriveToken!,
      );
    }
    final authorization =
        await _google!.authorizationClient.authorizationForScopes([
          driveScope,
        ]) ??
        (interactive
            ? await _google!.authorizationClient.authorizeScopes([driveScope])
            : null);
    if (authorization == null) {
      throw StateError(
        'Drive permission is needed. Tap Enable Drive backup to reconnect.',
      );
    }
    _lastDriveToken = authorization.accessToken;
    return {'Authorization': 'Bearer ${authorization.accessToken}'};
  }
}
