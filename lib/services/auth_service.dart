import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:newjuststock/services/api_config.dart';
import 'package:newjuststock/services/auth_models.dart';

class ApiResponse<T> {
  final bool ok;
  final int status;
  final T? data;
  final String message;
  final Map<String, dynamic>? raw;

  const ApiResponse({
    required this.ok,
    required this.status,
    required this.message,
    this.data,
    this.raw,
  });

  bool get isUnauthorized => status == 401 || status == 403;
}

class AuthService {
  const AuthService._();

  static Uri _authUri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return ApiConfig.buildUri('/api/auth$normalized', query);
  }

  static Map<String, String> _headers({String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final resolved = _trimmed(token);
    if (resolved != null && resolved.isNotEmpty) {
      headers['Authorization'] = 'Bearer $resolved';
    }
    return headers;
  }

  static Future<ApiResponse<AuthSession>> signup({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    String? referralCode,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'confirmPassword': confirmPassword,
    };
    final code = referralCode?.trim();
    if (code != null && code.isNotEmpty) {
      final normalizedCode = code.toUpperCase();
      payload['referralId'] = normalizedCode;
      payload['referralCode'] = normalizedCode;
    }
    return _postExpectSession(
      uri: _authUri('/signup'),
      payload: payload,
      defaultError: 'Failed to create account.',
    );
  }

  static Future<ApiResponse<AuthSession>> login({
    required String email,
    required String password,
  }) {
    final payload = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };
    return _postExpectSession(
      uri: _authUri('/login'),
      payload: payload,
      defaultError: 'Unable to sign in.',
    );
  }

  static Future<ApiResponse<AuthSession>> refreshToken({
    required String refreshToken,
    AuthSession? existing,
  }) {
    final payload = <String, dynamic>{
      'refreshToken': refreshToken.trim(),
    };
    return _postExpectSession(
      uri: _authUri('/refresh-token'),
      payload: payload,
      defaultError: 'Session refresh failed.',
      existing: existing,
    );
  }

  static Future<ApiResponse<ReferralListResponse>> fetchReferrals({
    required String accessToken,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = _authUri('/referrals', {
      'limit': limit,
      'offset': offset,
    });
    try {
      final response = await http.get(
        uri,
        headers: _headers(token: accessToken),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300 && json != null) {
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Referrals fetched.'),
          data: ReferralListResponse.fromJson(json),
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message: _extractMessage(json, status, 'Unable to load referrals.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<ReferralTreeResponse>> fetchReferralTree({
    required String accessToken,
    int depth = 3,
  }) async {
    final cappedDepth = depth.clamp(1, 5);
    final uri = _authUri('/referrals/tree', {'depth': cappedDepth});
    try {
      final response = await http.get(
        uri,
        headers: _headers(token: accessToken),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300 && json != null) {
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Referral tree loaded.'),
          data: ReferralTreeResponse.fromJson(json),
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message: _extractMessage(json, status, 'Unable to load referral tree.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<ReferralEarningsResponse>> fetchReferralEarnings({
    required String accessToken,
  }) async {
    final uri = _authUri('/referrals/earnings');
    try {
      final response = await http.get(
        uri,
        headers: _headers(token: accessToken),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300 && json != null) {
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Referral earnings loaded.'),
          data: ReferralEarningsResponse.fromJson(json),
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message:
            _extractMessage(json, status, 'Unable to load referral earnings.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<AuthUser>> fetchProfile({
    required String accessToken,
    AuthSession? existing,
  }) async {
    final uri = _authUri('/me');
    try {
      final response = await http.get(
        uri,
        headers: _headers(token: accessToken),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300) {
        final userPayload = _asMap(json?['user'] ?? json);
        final user = _mergeUserWithExisting(userPayload, existing);
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Profile loaded.'),
          data: user,
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message: _extractMessage(json, status, 'Unable to load profile.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<AuthUser>> updateProfile({
    required String accessToken,
    required String name,
    AuthSession? existing,
  }) async {
    final uri = _authUri('/me');
    final payload = {'name': name.trim()};
    try {
      final response = await http.put(
        uri,
        headers: _headers(token: accessToken),
        body: jsonEncode(payload),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300) {
        final userPayload = _asMap(json?['user'] ?? json);
        final user = _mergeUserWithExisting(userPayload, existing);
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Profile updated.'),
          data: user,
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message: _extractMessage(json, status, 'Unable to update profile.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<void>> logout({
    required String refreshToken,
    String? accessToken,
  }) async {
    final uri = _authUri('/logout');
    final payload = {'refreshToken': refreshToken};
    try {
      final response = await http.post(
        uri,
        headers: _headers(token: accessToken),
        body: jsonEncode(payload),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300) {
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Logged out.'),
          data: null,
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message: _extractMessage(json, status, 'Unable to log out.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<ReferralConfig>> fetchReferralConfig({
    required String accessToken,
  }) async {
    final uri = _authUri('/referrals/config');
    try {
      final response = await http.get(
        uri,
        headers: _headers(token: accessToken),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);
      if (status >= 200 && status < 300 && json != null) {
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Referral config loaded.'),
          data: ReferralConfig.fromJson(json),
          raw: json,
        );
      }
      return ApiResponse(
        ok: false,
        status: status,
        message:
            _extractMessage(json, status, 'Unable to load referral config.'),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static Future<ApiResponse<AuthSession>> _postExpectSession({
    required Uri uri,
    required Map<String, dynamic> payload,
    required String defaultError,
    AuthSession? existing,
  }) async {
    try {
      final response = await http.post(
        uri,
        headers: _headers(),
        body: jsonEncode(payload),
      );
      final status = response.statusCode;
      final json = _decodeJson(response.body);

      if (status >= 200 && status < 300 && json != null) {
        final session = _parseSession(json, existing: existing);
        return ApiResponse(
          ok: true,
          status: status,
          message: _extractMessage(json, status, 'Success'),
          data: session,
          raw: json,
        );
      }

      return ApiResponse(
        ok: false,
        status: status,
        message: _extractMessage(json, status, defaultError),
        data: null,
        raw: json,
      );
    } catch (error) {
      return ApiResponse(
        ok: false,
        status: -1,
        message: 'Network error: $error',
        data: null,
        raw: null,
      );
    }
  }

  static AuthSession _parseSession(
    Map<String, dynamic> payload, {
    AuthSession? existing,
  }) {
    final base = _asMap(payload);
    final tokensMap = _asMap(base['tokens'] ?? base);
    final userMap = _asMap(base['user'] ?? base);

    var tokens = AuthTokens.fromJson(
      tokensMap,
      fallbackRefreshToken: existing?.refreshToken,
    );
    final existingSession = existing;
    if (existingSession != null) {
      if (!tokens.hasRefreshToken &&
          existingSession.tokens.hasRefreshToken) {
        tokens = tokens.copyWith(
          refreshToken: existingSession.refreshToken,
          refreshTokenExpiresAt: existingSession.tokens.refreshTokenExpiresAt,
        );
      }
      if (tokens.accessTokenExpiresAt == null &&
          existingSession.tokens.accessTokenExpiresAt != null) {
        tokens = tokens.copyWith(
          accessTokenExpiresAt: existingSession.tokens.accessTokenExpiresAt,
        );
      }
      if (tokens.refreshTokenExpiresAt == null &&
          existingSession.tokens.refreshTokenExpiresAt != null) {
        tokens = tokens.copyWith(
          refreshTokenExpiresAt:
              existingSession.tokens.refreshTokenExpiresAt,
        );
      }
    }

    final user = _mergeUserWithExisting(userMap, existingSession);

    final termsAccepted =
        _parseBool(base['termsAccepted']) ??
            existingSession?.termsAccepted ??
            false;
    return AuthSession(
      tokens: tokens,
      user: user,
      termsAccepted: termsAccepted,
    );
  }

  static Map<String, dynamic>? _decodeJson(String source) {
    if (source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _extractMessage(
    Map<String, dynamic>? json,
    int status,
    String fallback,
  ) {
    if (json != null) {
      for (final key in const ['message', 'msg', 'error', 'detail']) {
        final value = json[key];
        final resolved = _trimmed(value);
        if (resolved != null && resolved.isNotEmpty) {
          return resolved;
        }
      }
      final errors = json['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        final resolved = _trimmed(first);
        if (resolved != null && resolved.isNotEmpty) {
          return resolved;
        }
      }
    }
    if (status == 409) {
      return 'Account already exists.';
    }
    return fallback;
  }

  static Map<String, dynamic> _asMap(dynamic source) {
    if (source is Map<String, dynamic>) {
      return Map<String, dynamic>.from(source);
    }
    if (source is Map) {
      return source.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, dynamic>{};
  }

  static AuthUser _mergeUserWithExisting(
    Map<String, dynamic> userMap,
    AuthSession? existing,
  ) {
    var user = AuthUser.fromJson(userMap);
    final session = existing;
    if (session == null) {
      return user;
    }

    if (user.id.trim().isEmpty) {
      user = user.copyWith(id: session.user.id);
    }
    if (user.name.trim().isEmpty) {
      user = user.copyWith(name: session.user.name);
    }
    if (user.email.trim().isEmpty) {
      user = user.copyWith(email: session.user.email);
    }
    if (user.phone == null && session.user.phone != null) {
      user = user.copyWith(phone: session.user.phone);
    }
    if (!userMap.containsKey('walletBalance')) {
      user = user.copyWith(walletBalancePaise: session.user.walletBalancePaise);
    }
    if (!userMap.containsKey('referralCode') &&
        session.user.referralCode != null) {
      user = user.copyWith(referralCode: session.user.referralCode);
    }
    if (!userMap.containsKey('referralShareLink') &&
        session.user.referralShareLink != null) {
      user = user.copyWith(
        referralShareLink: session.user.referralShareLink,
      );
    }
    if (!userMap.containsKey('referralCount')) {
      user = user.copyWith(referralCount: session.user.referralCount);
    }
    if (!userMap.containsKey('referralActivatedAt') &&
        session.user.referralActivatedAt != null) {
      user = user.copyWith(
        referralActivatedAt: session.user.referralActivatedAt,
      );
    }
    if (!userMap.containsKey('referredBy') &&
        session.user.referredBy != null) {
      user = user.copyWith(referredBy: session.user.referredBy);
    }
    return user;
  }

  static String? _trimmed(dynamic value) {
    final str = value?.toString();
    if (str == null) return null;
    final trimmed = str.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final str = value.toString().trim().toLowerCase();
    if (str.isEmpty) return null;
    if (str == 'true' || str == '1' || str == 'yes' || str == 'y' || str == 'on') {
      return true;
    }
    if (str == 'false' ||
        str == '0' ||
        str == 'no' ||
        str == 'n' ||
        str == 'off') {
      return false;
    }
    return null;
  }
}
