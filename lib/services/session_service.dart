import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';
import 'auth_service.dart';

export 'auth_models.dart';

class SessionService {
  static const _sessionKey = 'auth_session_v3';
  static const _legacySessionKey = 'auth_session_v2';
  static const _secureRefreshTokenKey = 'auth_refresh_token_v1';
  static const _tokenKey = 'auth_token';
  static const _nameKey = 'auth_name';
  static const _mobileKey = 'auth_mobile';
  static const _termsAcceptedKey = 'auth_terms_accepted';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static AuthSession? _cached;

  static Future<void> saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final secure = _secureStorage;
    final encoded = jsonEncode(
      session.toJson(includeRefreshToken: false),
    );
    await prefs.setString(_sessionKey, encoded);
    final refresh = session.refreshToken.trim();
    if (refresh.isNotEmpty) {
      await secure.write(key: _secureRefreshTokenKey, value: refresh);
    } else {
      await secure.delete(key: _secureRefreshTokenKey);
    }
    await _clearLegacyKeys(prefs);
    await prefs.remove(_legacySessionKey);
    _cached = session;
  }

  static Future<AuthSession?> loadSession({bool fromCache = true}) async {
    if (fromCache && _cached != null) {
      return _cached;
    }
    final prefs = await SharedPreferences.getInstance();
    final secure = _secureStorage;
    final refreshToken = await secure.read(key: _secureRefreshTokenKey);
    AuthSession? session;
    final raw = prefs.getString(_sessionKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> || decoded is Map) {
          final map = decoded is Map<String, dynamic>
              ? decoded
              : (decoded as Map<dynamic, dynamic>).map<String, dynamic>(
                  (key, value) => MapEntry(key.toString(), value),
                );
          session = AuthSession.fromJson(
            map,
            refreshTokenFallback: refreshToken,
          );
        }
      } catch (_) {
        session = null;
      }
    }

    if (session == null) {
      final legacyRaw = prefs.getString(_legacySessionKey);
      if (legacyRaw != null && legacyRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(legacyRaw);
          if (decoded is Map<String, dynamic> || decoded is Map) {
            final map = decoded is Map<String, dynamic>
                ? decoded
                : (decoded as Map<dynamic, dynamic>).map<String, dynamic>(
                    (key, value) => MapEntry(key.toString(), value),
                  );
            final migrated = AuthSession.fromJson(
              map,
              refreshTokenFallback: refreshToken,
            );
            await saveSession(migrated);
            session = migrated;
          }
        } catch (_) {
          session = null;
        }
      }
    }

    session ??= await _loadLegacySession(prefs, refreshToken);

    if (session != null) {
      if (refreshToken != null && refreshToken.trim().isNotEmpty) {
        session = session.copyWith(
          tokens: session.tokens.copyWith(refreshToken: refreshToken.trim()),
        );
      }
      _cached = session;
    }
    return session;
  }

  static Future<AuthSession?> ensureSession({bool refreshIfNeeded = true}) async {
    var session = await loadSession();
    if (session == null) return null;
    if (!refreshIfNeeded) return session;

    if (!session.tokens.shouldRefresh()) {
      return session;
    }

    if (!session.tokens.hasRefreshToken) {
      if (session.tokens.isAccessTokenExpired) {
        await clearSession();
        return null;
      }
      return session;
    }

    final response = await AuthService.refreshToken(
      refreshToken: session.tokens.refreshToken,
      existing: session,
    );

    if (!response.ok || response.data == null) {
      if (response.isUnauthorized) {
        await clearSession();
        return null;
      }
      return session;
    }

    final refreshed = response.data!;
    final normalized = refreshed.copyWith(
      termsAccepted: refreshed.termsAccepted || session.termsAccepted,
    );
    await saveSession(normalized);
    return normalized;
  }

  static Future<void> updateSession(AuthSession session) async {
    await saveSession(session);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_legacySessionKey);
    await _secureStorage.delete(key: _secureRefreshTokenKey);
    await _clearLegacyKeys(prefs);
    _cached = null;
  }

  static Future<AuthSession?> _loadLegacySession(
    SharedPreferences prefs,
    String? refreshToken,
  ) async {
    final token = _trimmed(prefs.getString(_tokenKey));
    final mobile = _trimmed(prefs.getString(_mobileKey));
    if (token == null || token.isEmpty || mobile == null || mobile.isEmpty) {
      return null;
    }
    final name = _trimmed(prefs.getString(_nameKey)) ?? '';
    final termsAccepted = prefs.getBool(_termsAcceptedKey) ?? false;

    final tokens = AuthTokens(
      accessToken: token,
      refreshToken: refreshToken ?? '',
    );
    final user = AuthUser(
      id: mobile,
      name: name.isEmpty ? 'User' : name,
      email: '',
      phone: mobile,
      walletBalancePaise: 0,
      referralCode: null,
      referralShareLink: null,
      referralCount: 0,
      referralActivatedAt: null,
      referredBy: null,
    );
    final session = AuthSession(
      tokens: tokens,
      user: user,
      termsAccepted: termsAccepted,
    );

    await saveSession(session);
    return session;
  }

  static Future<void> _clearLegacyKeys(SharedPreferences prefs) async {
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_mobileKey);
    await prefs.remove(_termsAcceptedKey);
  }

  static String? _trimmed(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
