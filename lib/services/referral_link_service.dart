import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReferralLinkService {
  ReferralLinkService._internal();

  static const _pendingReferralKey = 'pending_referral_code';
  static final ReferralLinkService _instance = ReferralLinkService._internal();

  StreamSubscription<Uri>? _subscription;
  AppLinks? _appLinks;
  final StreamController<String> _referralStreamController =
      StreamController<String>.broadcast();
  bool _isInitialized = false;

  static Stream<String> get onReferralCode =>
      _instance._referralStreamController.stream;

  static Future<void> initialize() => _instance._initialize();

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (kIsWeb) return;
    final platform = defaultTargetPlatform;
    final isSupportedPlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!isSupportedPlatform) return;

    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks!.getInitialAppLink();
      if (initialUri != null) {
        await _handleUri(initialUri);
      }
    } catch (error, stack) {
      debugPrint('ReferralLinkService: failed to get initial uri: $error');
      debugPrint('$stack');
    }

    _subscription = _appLinks!.uriLinkStream.listen(
      (uri) async {
        await _handleUri(uri);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('ReferralLinkService: uri stream error: $error');
        debugPrint('$stackTrace');
      },
      cancelOnError: false,
    );
  }

  Future<void> _handleUri(Uri uri) async {
    final code = _extractReferralCode(uri);
    if (code == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingReferralKey, code);

    if (!_referralStreamController.isClosed) {
      _referralStreamController.add(code);
    }
  }

  String? _extractReferralCode(Uri uri) {
    final queryCode =
        uri.queryParameters['ref'] ??
        uri.queryParameters['code'] ??
        uri.queryParameters['referral'];

    final candidate = (queryCode ?? _segmentFallback(uri))?.trim();
    if (candidate == null || candidate.isEmpty) return null;

    final cleaned = Uri.decodeComponent(candidate).toUpperCase();
    return _looksLikeReferralCode(cleaned) ? cleaned : null;
  }

  String? _segmentFallback(Uri uri) {
    if (uri.pathSegments.isEmpty) return null;
    final last = uri.pathSegments.last.trim();
    if (last.isEmpty) return null;
    final upper = last.toUpperCase();
    return _looksLikeReferralCode(upper) ? upper : null;
  }

  bool _looksLikeReferralCode(String value) {
    return RegExp(r'^[A-Z0-9]{4,}$').hasMatch(value);
  }

  static Future<String?> getPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingReferralKey);
    return code?.trim().isEmpty == true ? null : code;
  }

  static Future<void> clearPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingReferralKey);
  }

  static Future<void> setPendingReferralCode(String code) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingReferralKey, cleaned);
    if (!_instance._referralStreamController.isClosed) {
      _instance._referralStreamController.add(cleaned);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _referralStreamController.close();
  }
}
