import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_config.dart';

/// Anonymous Firebase authentication over the Identity Toolkit REST API.
///
/// `firebase_auth` has no Windows support, so this signs up an anonymous user
/// directly and caches the refresh token. Keeping the *same* uid across
/// restarts matters: the household's `members` list is keyed by uid, and a new
/// uid each launch would need re-joining and would litter the member list.
class AuthService {
  static const _refreshTokenKey = 'firebase_refresh_token';
  static const _uidKey = 'firebase_uid';

  String? _idToken;
  DateTime? _idTokenExpiry;
  String? _uid;

  String? get uid => _uid;

  /// Returns a valid ID token, signing up or refreshing as needed.
  Future<String> idToken() async {
    if (_idToken != null &&
        _idTokenExpiry != null &&
        DateTime.now().isBefore(_idTokenExpiry!)) {
      return _idToken!;
    }

    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);

    if (refreshToken != null) {
      try {
        return await _refresh(refreshToken);
      } catch (_) {
        // Refresh token revoked or expired — fall through to a fresh sign-up.
      }
    }
    return _signUpAnonymously();
  }

  Future<String> _signUpAnonymously() async {
    final response = await http.post(
      Uri.parse('${FirebaseConfig.identityBase}/accounts:signUp?key=${FirebaseConfig.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );

    if (response.statusCode != 200) {
      throw Exception('התחברות אנונימית נכשלה: ${_errorMessage(response.body)}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _store(
      idToken: data['idToken'] as String,
      refreshToken: data['refreshToken'] as String,
      uid: data['localId'] as String,
      expiresInSeconds: int.parse(data['expiresIn'] as String),
    );
    return _idToken!;
  }

  Future<String> _refresh(String refreshToken) async {
    final response = await http.post(
      Uri.parse('${FirebaseConfig.secureTokenBase}/token?key=${FirebaseConfig.apiKey}'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );

    if (response.statusCode != 200) {
      throw Exception('רענון החיבור נכשל: ${_errorMessage(response.body)}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _store(
      idToken: data['id_token'] as String,
      refreshToken: data['refresh_token'] as String,
      uid: data['user_id'] as String,
      expiresInSeconds: int.parse(data['expires_in'] as String),
    );
    return _idToken!;
  }

  Future<void> _store({
    required String idToken,
    required String refreshToken,
    required String uid,
    required int expiresInSeconds,
  }) async {
    _idToken = idToken;
    _uid = uid;
    // Refresh a minute early so a token never expires mid-request.
    _idTokenExpiry =
        DateTime.now().add(Duration(seconds: expiresInSeconds - 60));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_uidKey, uid);
  }

  Future<void> loadCachedUid() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = prefs.getString(_uidKey);
  }

  static String _errorMessage(String body) {
    try {
      return jsonDecode(body)['error']?['message']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}
