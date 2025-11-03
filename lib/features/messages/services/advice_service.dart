import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:newjuststock/services/api_config.dart';
import 'package:newjuststock/services/session_service.dart';

class AdviceSummary {
  final String id;
  final String category; // canonical uppercase
  final DateTime createdAt;
  final int price; // rupees

  const AdviceSummary({
    required this.id,
    required this.category,
    required this.createdAt,
    required this.price,
  });

  factory AdviceSummary.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    DateTime ts;
    if (created is String) {
      ts = DateTime.tryParse(created) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }
    int price = 0;
    final p = json['price'];
    if (p is int) price = p; else if (p is num) price = p.round(); else if (p is String) price = int.tryParse(p) ?? 0;

    return AdviceSummary(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      createdAt: ts,
      price: price,
    );
  }
}

class AdviceDetail {
  final String id;
  final String category;
  final String text;
  final String? buy;
  final String? target;
  final String? stoploss;
  final DateTime createdAt;
  final int price;

  const AdviceDetail({
    required this.id,
    required this.category,
    required this.text,
    required this.createdAt,
    required this.price,
    this.buy,
    this.target,
    this.stoploss,
  });

  factory AdviceDetail.fromJson(Map<String, dynamic> json) {
    final a = json['advice'] is Map<String, dynamic> ? json['advice'] as Map<String, dynamic> : json;
    final created = a['createdAt'];
    DateTime ts;
    if (created is String) {
      ts = DateTime.tryParse(created) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }
    int price = 0;
    final p = a['price'];
    if (p is int) price = p; else if (p is num) price = p.round(); else if (p is String) price = int.tryParse(p) ?? 0;

    return AdviceDetail(
      id: (a['id'] ?? a['_id'] ?? '').toString(),
      category: (a['category'] ?? '').toString(),
      text: (a['text'] ?? '').toString(),
      buy: a['buy']?.toString(),
      target: a['target']?.toString(),
      stoploss: a['stoploss']?.toString(),
      createdAt: ts,
      price: price,
    );
  }
}

class AdviceApiResult<T> {
  final bool ok;
  final T? data;
  final String message;
  final bool unauthorized;
  final int statusCode;

  const AdviceApiResult({
    required this.ok,
    required this.message,
    required this.statusCode,
    this.data,
    this.unauthorized = false,
  });

  factory AdviceApiResult.unauthorized({
    String message = 'Session expired. Please log in.',
  }) {
    return AdviceApiResult(
      ok: false,
      message: message,
      statusCode: 401,
      data: null,
      unauthorized: true,
    );
  }
}

class AdviceService {
  static Uri _adviceListUri({String? category, int? page, int? limit}) {
    final qp = <String, dynamic>{};
    if (category != null && category.trim().isNotEmpty) qp['category'] = category.trim();
    if (page != null) qp['page'] = page;
    if (limit != null) qp['limit'] = limit;
    return ApiConfig.buildUri('/api/advice-v2', qp);
  }

  static Uri _adviceUnlockUri(String id) => ApiConfig.buildUri('/api/advice-v2/$id/unlock');
  static Uri _adviceUnlockLatestUri(String category) {
    final slug = category.trim().toLowerCase();
    return ApiConfig.buildUri('/api/advice-v2/$slug/unlock-latest');
  }

  static Future<AdviceApiResult<List<AdviceSummary>>> fetchList({
    required String category,
    int page = 1,
    int limit = 20,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) return AdviceApiResult.unauthorized();

    final uri = _adviceListUri(category: category, page: page, limit: limit);
    try {
      final res = await http.get(uri, headers: _headers(authToken));
      final status = res.statusCode;
      if (status == 401 || status == 403) return AdviceApiResult.unauthorized();
      Map<String, dynamic>? json;
      if (res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (_) {}
      }
      if (status >= 200 && status < 300 && json != null) {
        final items = (json['items'] as List? ?? const [])
            .map((e) => AdviceSummary.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false);
        return AdviceApiResult(ok: true, message: 'ok', statusCode: status, data: items);
      }
      final msg = json != null ? _extractMessage(json, status, res.body, 'Failed to load advice') : (res.body.isNotEmpty ? res.body : 'Failed to load advice');
      return AdviceApiResult(ok: false, message: msg, statusCode: status, data: null);
    } catch (e) {
      return AdviceApiResult(ok: false, message: 'Network error: $e', statusCode: -1, data: null);
    }
  }

  static Future<AdviceApiResult<AdviceSummary?>> fetchLatest({
    required String category,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) return AdviceApiResult.unauthorized();
    final uri = ApiConfig.buildUri('/api/advice-v2/latest', {'category': category});
    try {
      final res = await http.get(uri, headers: _headers(authToken));
      final status = res.statusCode;
      if (status == 401 || status == 403) return AdviceApiResult.unauthorized();
      Map<String, dynamic>? json;
      if (res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (_) {}
      }
      if (status >= 200 && status < 300 && json != null) {
        final adv = json['advice'];
        if (adv == null) {
          return AdviceApiResult(ok: true, message: 'ok', statusCode: status, data: null);
        }
        final data = AdviceSummary.fromJson((adv as Map).cast<String, dynamic>());
        return AdviceApiResult(ok: true, message: 'ok', statusCode: status, data: data);
      }
      final msg = json != null ? _extractMessage(json, status, res.body, 'Failed to load latest') : (res.body.isNotEmpty ? res.body : 'Failed to load latest');
      return AdviceApiResult(ok: false, message: msg, statusCode: status, data: null);
    } catch (e) {
      return AdviceApiResult(ok: false, message: 'Network error: $e', statusCode: -1, data: null);
    }
  }

  static Future<AdviceApiResult<AdviceDetail>> unlock({
    required String adviceId,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) return AdviceApiResult.unauthorized();

    final uri = _adviceUnlockUri(adviceId);
    try {
      final res = await http.post(uri, headers: _headers(authToken));
      final status = res.statusCode;
      Map<String, dynamic>? json;
      if (res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (_) {}
      }
      if (status == 401 || status == 403) return AdviceApiResult.unauthorized();
      if (status == 402) {
        final msg = json != null ? _extractMessage(json, status, res.body, 'Insufficient funds') : 'Insufficient funds';
        return AdviceApiResult(ok: false, message: msg, statusCode: status, data: null);
      }
      if (status >= 200 && status < 300 && json != null) {
        return AdviceApiResult(
          ok: true,
          message: 'ok',
          statusCode: status,
          data: AdviceDetail.fromJson(json),
        );
      }
      final msg = json != null ? _extractMessage(json, status, res.body, 'Unlock failed') : (res.body.isNotEmpty ? res.body : 'Unlock failed');
      return AdviceApiResult(ok: false, message: msg, statusCode: status, data: null);
    } catch (e) {
      return AdviceApiResult(ok: false, message: 'Network error: $e', statusCode: -1, data: null);
    }
  }

  static Future<AdviceApiResult<AdviceDetail>> unlockLatestByCategory({
    required String category,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) return AdviceApiResult.unauthorized();

    final uri = _adviceUnlockLatestUri(category);
    try {
      final res = await http.post(uri, headers: _headers(authToken));
      final status = res.statusCode;
      Map<String, dynamic>? json;
      if (res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (_) {}
      }
      if (status == 401 || status == 403) return AdviceApiResult.unauthorized();
      if (status == 402) {
        final msg = json != null
            ? _extractMessage(json, status, res.body, 'Insufficient funds')
            : 'Insufficient funds';
        return AdviceApiResult(ok: false, message: msg, statusCode: status, data: null);
      }
      if (status >= 200 && status < 300 && json != null) {
        return AdviceApiResult(
          ok: true,
          message: 'ok',
          statusCode: status,
          data: AdviceDetail.fromJson(json),
        );
      }
      final msg = json != null
          ? _extractMessage(json, status, res.body, 'Unlock latest failed')
          : (res.body.isNotEmpty ? res.body : 'Unlock latest failed');
      return AdviceApiResult(ok: false, message: msg, statusCode: status, data: null);
    } catch (e) {
      return AdviceApiResult(ok: false, message: 'Network error: $e', statusCode: -1, data: null);
    }
  }

  static Future<String?> _resolveToken({String? token}) async {
    if (token != null && token.trim().isNotEmpty) return token.trim();
    final session = await SessionService.ensureSession();
    if (session == null || !session.isValid) return null;
    return session.accessToken.trim();
  }

  static Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  static String _extractMessage(
    Map<String, dynamic> json,
    int status,
    String raw,
    String fallback,
  ) {
    const keys = ['message', 'msg', 'error', 'detail'];
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    if (json['errors'] is List && (json['errors'] as List).isNotEmpty) {
      return (json['errors'] as List).first.toString();
    }
    if (raw.isNotEmpty) return raw;
    return fallback;
  }
}
