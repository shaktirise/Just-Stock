import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:newjuststock/services/api_config.dart';

import 'package:newjuststock/services/session_service.dart';

class WalletApiResult<T> {
  final bool ok;
  final T? data;
  final String message;
  final bool unauthorized;
  final int statusCode;

  const WalletApiResult({
    required this.ok,
    required this.message,
    required this.statusCode,
    this.data,
    this.unauthorized = false,
  });

  factory WalletApiResult.unauthorized({
    String message = 'Session expired. Please log in.',
  }) {
    return WalletApiResult(
      ok: false,
      message: message,
      statusCode: 401,
      data: null,
      unauthorized: true,
    );
  }
}

class WalletBalance {
  final int balancePaise;

  const WalletBalance({required this.balancePaise});

  double get balanceRupees => balancePaise / 100.0;

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    final balance = json['balancePaise'];
    if (balance is int) {
      return WalletBalance(balancePaise: balance);
    }
    if (balance is String) {
      return WalletBalance(balancePaise: int.tryParse(balance) ?? 0);
    }
    return const WalletBalance(balancePaise: 0);
  }
}

class WalletOrder {
  final String key;
  final String orderId;
  final int amountPaise;
  final int? amountRupees;
  final String currency;

  const WalletOrder({
    required this.key,
    required this.orderId,
    required this.amountPaise,
    this.amountRupees,
    required this.currency,
  });

  int resolvedAmountPaise({required int fallbackRupees}) {
    if (amountPaise > 0) return amountPaise;
    if (fallbackRupees > 0) return fallbackRupees * 100;
    if (amountRupees != null && amountRupees! > 0) {
      return amountRupees! * 100;
    }
    return 0;
  }

  factory WalletOrder.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.round();
      if (value == null) return 0;
      return int.tryParse(value.toString()) ?? 0;
    }

    final rawAmount = parseInt(json['amount']);
    final amountInPaise = parseInt(
      json['amountInPaise'] ?? json['amount_paise'] ?? json['amount_in_paise'],
    );
    final amountInRupees = parseInt(
      json['amountInRupees'] ?? json['amount_rupees'] ?? json['amount_rupee'],
    );

    int resolvedPaise = 0;
    if (amountInPaise > 0) {
      resolvedPaise = amountInPaise;
    } else if (rawAmount > 0) {
      resolvedPaise = rawAmount;
    } else if (amountInRupees > 0) {
      resolvedPaise = amountInRupees * 100;
    }

    final resolvedRupees = amountInRupees > 0
        ? amountInRupees
        : (resolvedPaise > 0 ? resolvedPaise ~/ 100 : null);

    return WalletOrder(
      key: json['key']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      amountPaise: resolvedPaise,
      amountRupees: resolvedRupees == 0 ? null : resolvedRupees,
      currency: json['currency']?.toString() ?? 'INR',
    );
  }
}

class WalletDebitReceipt {
  final int debitedPaise;
  final int baseAmountPaise;
  final int gstAmountPaise;
  final String? note;

  const WalletDebitReceipt({
    required this.debitedPaise,
    required this.baseAmountPaise,
    required this.gstAmountPaise,
    this.note,
  });

  double get debitedRupees => debitedPaise / 100.0;
  double get baseAmountRupees => baseAmountPaise / 100.0;
  double get gstAmountRupees => gstAmountPaise / 100.0;

  factory WalletDebitReceipt.fromJson(Map<String, dynamic> json) {
    final debited = json['debitedPaise'] ?? json['debited_paise'];
    final base = json['baseAmountPaise'] ?? json['base_amount_paise'];
    final gst = json['gstAmountPaise'] ?? json['gst_amount_paise'];
    return WalletDebitReceipt(
      debitedPaise: debited is int
          ? debited
          : int.tryParse(debited?.toString() ?? '') ?? 0,
      baseAmountPaise: base is int
          ? base
          : int.tryParse(base?.toString() ?? '') ?? 0,
      gstAmountPaise: gst is int
          ? gst
          : int.tryParse(gst?.toString() ?? '') ?? 0,
      note: json['note']?.toString(),
    );
  }
}

class WalletService {
  static String get _baseUrl => '${ApiConfig.apiBaseUrl}/api/wallet';
  static const int _minimumTopUpRupees = 1;
  static const int minimumTopUpRupees = _minimumTopUpRupees;

  const WalletService._();

  static Future<WalletApiResult<WalletBalance>> fetchBalance({
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) {
      return WalletApiResult.unauthorized();
    }

    final uri = Uri.parse('$_baseUrl/balance');
    try {
      final res = await http.get(uri, headers: _headers(authToken));
      return _parseResponse(
        res,
        onSuccess: (json) => WalletBalance.fromJson(json),
        defaultMessage: 'Failed to fetch balance.',
      );
    } catch (e) {
      return WalletApiResult(
        ok: false,
        statusCode: -1,
        message: 'Network error: $e',
        data: null,
      );
    }
  }

  static Future<WalletApiResult<WalletOrder>> createTopUpOrder({
    required int amountInRupees,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) {
      return WalletApiResult.unauthorized();
    }

    if (amountInRupees < _minimumTopUpRupees) {
      return WalletApiResult(
        ok: false,
        statusCode: 400,
        message: 'Minimum top-up is ₹$_minimumTopUpRupees.',
        data: null,
      );
    }

    final uri = Uri.parse('$_baseUrl/topups/create-order');
    final amountInPaise = amountInRupees * 100;
    final body = jsonEncode({
      'amountInRupees': amountInRupees,
      'amountInPaise': amountInPaise,
      'amount': amountInPaise,
      'currency': 'INR',
    });
    try {
      final res = await http.post(
        uri,
        headers: _headers(authToken),
        body: body,
      );
      return _parseResponse(
        res,
        onSuccess: (json) => WalletOrder.fromJson(json),
        defaultMessage: 'Failed to create order.',
      );
    } catch (e) {
      return WalletApiResult(
        ok: false,
        statusCode: -1,
        message: 'Network error: $e',
        data: null,
      );
    }
  }

  static Future<WalletApiResult<Map<String, dynamic>>> verifyTopUp({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required int amountInRupees,
    int? amountInPaise,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) {
      return WalletApiResult.unauthorized();
    }

    final uri = Uri.parse('$_baseUrl/topups/verify');
    final resolvedPaise = amountInPaise ?? (amountInRupees * 100);
    final payload = jsonEncode({
      'razorpay_order_id': razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature': razorpaySignature,
      'amountInRupees': amountInRupees,
      'amountInPaise': resolvedPaise,
      'amount': resolvedPaise,
      'currency': 'INR',
    });

    try {
      final res = await http.post(
        uri,
        headers: _headers(authToken),
        body: payload,
      );
      return _parseResponse(
        res,
        onSuccess: (json) => json,
        defaultMessage: 'Failed to verify payment.',
      );
    } catch (e) {
      return WalletApiResult(
        ok: false,
        statusCode: -1,
        message: 'Network error: $e',
        data: null,
      );
    }
  }

  static Future<WalletApiResult<WalletDebitReceipt>> debit({
    required int amountInRupees,
    required String note,
    String? token,
  }) async {
    final authToken = await _resolveToken(token: token);
    if (authToken == null) {
      return WalletApiResult.unauthorized();
    }

    if (amountInRupees <= 0) {
      return WalletApiResult(
        ok: false,
        statusCode: 400,
        message: 'Debit amount must be greater than zero.',
        data: null,
      );
    }

    final uri = Uri.parse('$_baseUrl/debit');
    final payload = jsonEncode({
      'amountInRupees': amountInRupees,
      'note': note,
    });

    try {
      final res = await http.post(
        uri,
        headers: _headers(authToken),
        body: payload,
      );
      return _parseResponse(
        res,
        onSuccess: (json) => WalletDebitReceipt.fromJson(json),
        defaultMessage: 'Failed to debit wallet.',
      );
    } catch (e) {
      return WalletApiResult(
        ok: false,
        statusCode: -1,
        message: 'Network error: $e',
        data: null,
      );
    }
  }

  static Future<String?> _resolveToken({String? token}) async {
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }
    final session = await SessionService.ensureSession();
    if (session == null || !session.isValid) {
      return null;
    }
    return session.accessToken.trim();
  }

  static Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static WalletApiResult<T> _parseResponse<T>(
    http.Response response, {
    required T Function(Map<String, dynamic> json) onSuccess,
    required String defaultMessage,
  }) {
    final status = response.statusCode;
    Map<String, dynamic>? json;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        }
      } catch (_) {
        json = null;
      }
    }

    if (status == 401 || status == 403) {
      return WalletApiResult.unauthorized();
    }

    if (status >= 200 && status < 300) {
      final payload = json ?? <String, dynamic>{};
      return WalletApiResult(
        ok: true,
        statusCode: status,
        message: _extractMessage(
          payload,
          status,
          response.body,
          defaultMessage,
        ),
        data: onSuccess(payload),
      );
    }

    final message = json != null
        ? _extractMessage(json, status, response.body, defaultMessage)
        : (response.body.isNotEmpty ? response.body : defaultMessage);
    return WalletApiResult(
      ok: false,
      statusCode: status,
      message: message,
      data: null,
    );
  }

  static String _extractMessage(
    Map<String, dynamic> json,
    int status,
    String raw,
    String fallback,
  ) {
    const keys = ['message', 'msg', 'error', 'detail'];
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }

    if (json['errors'] is List && (json['errors'] as List).isNotEmpty) {
      return (json['errors'] as List).first.toString();
    }

    if (raw.isNotEmpty) {
      return raw;
    }
    return fallback;
  }
}
