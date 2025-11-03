import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/features/profile/presentation/pages/profile_page.dart';
import 'package:newjuststock/features/profile/presentation/pages/referral_earnings_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/session_service.dart';
import 'package:newjuststock/services/segment_service.dart';
import 'package:newjuststock/services/gallery_service.dart';
import 'package:newjuststock/services/support_config.dart';
import 'package:newjuststock/wallet/ui/wallet_screen.dart';
import 'package:newjuststock/wallet/services/wallet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newjuststock/features/messages/models/admin_message.dart';
import 'package:newjuststock/features/messages/presentation/pages/admin_message_page.dart';
import 'package:newjuststock/features/messages/services/advice_service.dart';
import 'package:newjuststock/features/messages/presentation/pages/advice_list_page.dart';

// Market data model
class MarketData {
  final String symbol;
  final double price;
  final double change;
  final double changePercent;
  final List<double> chartData;

  MarketData({
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.chartData,
  });

  factory MarketData.fromJson(Map<String, dynamic> json) {
    return MarketData(
      symbol: json['symbol'] ?? '',
      price: (json['price'] ?? 0.0).toDouble(),
      change: (json['change'] ?? 0.0).toDouble(),
      changePercent: (json['changePercent'] ?? 0.0).toDouble(),
      chartData: List<double>.from(json['chartData'] ?? []),
    );
  }
}

class HomePage extends StatefulWidget {
  final AuthSession session;

  const HomePage({super.key, required this.session});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late AuthSession _session;

  static const List<String> _segmentKeys = [
    'stocks',
    'future',
    'options',
    'commodity',
  ];
  // Only fetch segments for keys supported by backend segments API to avoid noise.
  static const List<String> _segmentFetchKeys = [
    'stocks',
    'commodity',
  ];

  static const Color _segmentBackgroundColor = Color(
    0xFF8B0000,
  ); // Dark red shade

  static const List<_SegmentDescriptor> _segmentDescriptors = [
    _SegmentDescriptor(
      key: 'stocks',
      title: 'STOCKS',
      icon: Icons.auto_graph,
      tone: _SegmentTone.primary,
    ),
    _SegmentDescriptor(
      key: 'future',
      title: 'FUTURE',
      icon: Icons.trending_up,
      tone: _SegmentTone.secondary,
    ),
    _SegmentDescriptor(
      key: 'options',
      title: 'OPTIONS',
      icon: Icons.swap_vert_circle_outlined,
      tone: _SegmentTone.primary,
    ),
    _SegmentDescriptor(
      key: 'commodity',
      title: 'COMMODITY',
      icon: Icons.analytics_outlined,
      tone: _SegmentTone.secondary,
    ),
  ];

  final Map<String, SegmentMessage> _segmentMessages = {};
  final Map<String, String> _acknowledgedMessages = {};
  // Advice V2 latest per category (canonical uppercase)
  final Map<String, String> _latestAdviceV2Ids = {};
  final Map<String, String> _ackAdviceV2Ids = {};
  bool _loadingSegments = false;
  String? _segmentsError;

  List<GalleryImage> _galleryImages = const [];
  bool _loadingGallery = false;
  String? _galleryError;
  late final AnimationController _supportAnimationController;
  late final Animation<double> _supportPulse;
  late final Animation<Offset> _supportNudge;
  bool _hasUnreadSegments = false;

  // Market data
  Map<String, MarketData> _marketData = {};
  bool _loadingMarketData = false;
  String? _marketDataError;
  Timer? _marketDataTimer;
  Timer? _adviceLatestTimer;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _supportAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _supportPulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _supportAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _supportNudge =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.06)).animate(
          CurvedAnimation(
            parent: _supportAnimationController,
            curve: Curves.easeInOut,
          ),
        );
    _loadSegments();
    _loadAdviceV2Latest();
    _loadGallery();
    _loadSeenAcks();
    _loadAdviceV2Acks();
    // Enable market data using free public endpoints with graceful fallback
    _loadMarketData();
    _startMarketDataUpdates();
    _startAdviceLatestUpdates();
  }

  @override
  void dispose() {
    _marketDataTimer?.cancel();
    _adviceLatestTimer?.cancel();
    _supportAnimationController.dispose();
    super.dispose();
  }

  String get _displayName {
    final trimmed = _session.user.name.trim();
    return trimmed.isEmpty ? 'User' : trimmed;
  }

  String get _initial => _displayName[0].toUpperCase();

  String get _accessToken => _session.accessToken.trim();

  Future<void> _handleSessionExpired({bool fromSegments = false}) async {
    await SessionService.clearSession();
    if (!mounted) return;
    if (!fromSegments) {
      _showSnack('Session expired. Please log in again.');
    }
    Navigator.of(
      context,
    ).pushAndRemoveUntil(fadeRoute(const LoginPage()), (route) => false);
  }

  Future<void> _loadSegments({bool silently = false}) async {
    if (!silently) {
      setState(() {
        _loadingSegments = true;
        _segmentsError = null;
      });
    }

    final refreshedSession = await SessionService.ensureSession();
    if (!mounted) return;
    if (refreshedSession == null) {
      setState(() {
        _loadingSegments = false;
        _segmentsError = 'Session expired. Please log in again.';
      });
      await _handleSessionExpired(fromSegments: true);
      return;
    }
    _session = refreshedSession;

    final result = await SegmentService.fetchSegments(
      _segmentFetchKeys,
      token: _accessToken,
    );

    if (!mounted) return;

    if (result.unauthorized) {
      if (!silently) _showSnack('Session expired. Please log in again.');
      setState(() {
        _loadingSegments = false;
        _segmentsError = 'Session expired. Please log in again.';
      });
      await _handleSessionExpired(fromSegments: true);
      return;
    }

    final segments = result.segments;

    setState(() {
      _loadingSegments = false;

      if (segments.isNotEmpty) {
        for (final entry in segments.entries) {
          _segmentMessages[entry.key] = entry.value;
          if (!entry.value.hasMessage) {
            _acknowledgedMessages.remove(entry.key);
          }
        }
      }

      final missingKeys = _segmentFetchKeys
          .where((key) => !segments.containsKey(key))
          .toList();
      if (segments.isEmpty) {
        _segmentsError =
            'Unable to fetch market updates right now. Pull to refresh to try again.';
      } else if (missingKeys.isNotEmpty) {
        _segmentsError =
            'Some market updates are unavailable. Pull to refresh to retry.';
      } else {
        _segmentsError = null;
      }
      _refreshUnreadIndicators(skipSetState: true);
    });

    if (!silently) {
      if (segments.isEmpty) {
        _showSnack(
          'Unable to fetch the latest market updates. Please try again.',
        );
      } else {
        final missingKeys = _segmentFetchKeys
            .where((key) => !segments.containsKey(key))
            .toList();
        if (missingKeys.isNotEmpty) {
          _showSnack('Some market updates could not be refreshed.');
        }
      }
    }
  }

  Future<void> _loadAdviceV2Latest() async {
    final refreshedSession = await SessionService.ensureSession();
    if (!mounted) return;
    if (refreshedSession == null) {
      await _handleSessionExpired(fromSegments: true);
      return;
    }
    _session = refreshedSession;
    const cats = ['STOCKS', 'FUTURE', 'OPTIONS', 'COMMODITY'];
    for (final cat in cats) {
      try {
        final res = await AdviceService.fetchLatest(category: cat, token: _accessToken);
        if (res.ok && res.data != null) {
          _latestAdviceV2Ids[cat] = res.data!.id;
        }
      } catch (_) {}
    }
    if (mounted) _refreshUnreadIndicators(skipSetState: false);
  }

  Future<void> _loadGallery({bool silently = false}) async {
    if (!silently) {
      setState(() {
        _galleryError = null;
      });
    }
    setState(() {
      _loadingGallery = true;
    });

    List<GalleryImage>? images;
    String? error;

    try {
      final fetched = await GalleryService.fetchImages(limit: 3);
      final sorted = List<GalleryImage>.from(fetched)
        ..sort(
          (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        );
      images = sorted.take(3).toList(growable: false);
    } catch (e) {
      if (e is GalleryFetchException) {
        error = e.message;
      } else {
        error = 'Unable to load images. Please try again.';
      }
    }

    if (!mounted) return;

    setState(() {
      _loadingGallery = false;
      if (images != null) {
        _galleryImages = images;
        _galleryError = null;
      } else {
        _galleryError = error;
      }
    });
  }

  void _updateSupportAnimation() {
    if (_hasUnreadSegments) {
      if (!_supportAnimationController.isAnimating) {
        _supportAnimationController
          ..reset()
          ..repeat(reverse: true);
      }
    } else if (_supportAnimationController.isAnimating ||
        _supportAnimationController.value != 0.0) {
      _supportAnimationController
        ..stop()
        ..reset();
    }
  }

  void _refreshUnreadIndicators({bool skipSetState = false}) {
    final hasUnread = _segmentKeys.any(_isSegmentUnread) || _hasUnreadAdviceV2();
    if (_hasUnreadSegments == hasUnread) {
      if (!hasUnread) {
        _updateSupportAnimation();
      }
      return;
    }
    if (skipSetState) {
      _hasUnreadSegments = hasUnread;
      _updateSupportAnimation();
    } else {
      setState(() {
        _hasUnreadSegments = hasUnread;
      });
      _updateSupportAnimation();
    }
  }

  bool _isSegmentUnread(String key) {
    final segment = _segmentMessages[key];
    if (segment == null) return false;
    final message = segment.message.trim();
    if (message.isEmpty) return false;
    final seenMessage = _acknowledgedMessages[key];
    return seenMessage != message;
  }

  bool _hasUnreadAdviceV2() {
    for (final entry in _latestAdviceV2Ids.entries) {
      final seenId = _ackAdviceV2Ids[entry.key];
      if (seenId == null || seenId != entry.value) return true;
    }
    return false;
  }

  bool _isAdviceV2KeyUnread(String segmentKey) {
    final cat = _canonicalCategory(segmentKey);
    if (cat == null) return false;
    final latest = _latestAdviceV2Ids[cat];
    if (latest == null || latest.isEmpty) return false;
    final seen = _ackAdviceV2Ids[cat];
    return seen == null || seen != latest;
  }

  // Open category list of advice (pay-per-message)
  Future<void> _handleSegmentTap(_HomeItem item) async {
    final category = _canonicalCategory(item.segmentKey);
    if (category == null) {
      _showSnack('Invalid category');
      return;
    }
    final latestId = _latestAdviceV2Ids[category];
    if (latestId != null && latestId.isNotEmpty) {
      await _saveAdviceV2Ack(category, latestId);
    }
    await Navigator.of(context).push(
      fadeRoute(AdviceListPage(category: category, title: item.title)),
    );
  }

  String? _canonicalCategory(String key) {
    switch (key.toLowerCase()) {
      case 'stocks':
        return 'STOCKS';
      case 'future':
      case 'futures':
        return 'FUTURE';
      case 'options':
      case 'option':
        return 'OPTIONS';
      case 'commodity':
      case 'comodity':
        return 'COMMODITY';
    }
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _syncSession({bool silent = false}) async {
    final maybeSession = await SessionService.ensureSession();
    if (!mounted) return;
    if (maybeSession == null) {
      await _handleSessionExpired(fromSegments: silent);
      return;
    }

    var session = maybeSession;

    final profileResponse = await AuthService.fetchProfile(
      accessToken: session.accessToken,
      existing: session,
    );
    if (!mounted) return;
    if (profileResponse.isUnauthorized) {
      await _handleSessionExpired(fromSegments: silent);
      return;
    }
    if (profileResponse.ok && profileResponse.data != null) {
      session = session.copyWith(user: profileResponse.data!);
      await SessionService.saveSession(session);
    } else if (!silent && profileResponse.message.isNotEmpty) {
      _showSnack(profileResponse.message);
    }

    setState(() => _session = session);
  }

  Future<void> _loadSeenAcks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('segment_ack_v1');
    if (raw == null || raw.isEmpty) return;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final parsed = <String, String>{};
      for (final e in map.entries) {
        final v = e.value?.toString() ?? '';
        if (v.isNotEmpty) parsed[e.key] = v;
      }
      if (!mounted) return;
      setState(() {
        _acknowledgedMessages
          ..clear()
          ..addAll(parsed);
        _refreshUnreadIndicators(skipSetState: true);
      });
    } catch (_) {}
  }

  Future<void> _loadAdviceV2Acks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('advice_v2_seen_ids_v1');
    if (raw == null || raw.isEmpty) return;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final parsed = <String, String>{};
      for (final e in map.entries) {
        final v = e.value?.toString() ?? '';
        if (v.isNotEmpty) parsed[e.key] = v;
      }
      if (!mounted) return;
      setState(() {
        _ackAdviceV2Ids
          ..clear()
          ..addAll(parsed);
        _refreshUnreadIndicators(skipSetState: true);
      });
    } catch (_) {}
  }

  Future<void> _loadMarketData({bool silently = false}) async {
    if (!silently) {
      setState(() {
        _loadingMarketData = true;
        _marketDataError = null;
      });
    }

    try {
      // Yahoo Finance APIs (public). First fetch quotes, then small chart data per symbol.
      const symbols = <String, String>{
        'NIFTY 50': '^NSEI',
        'BANKNIFTY': '^NSEBANK',
        'SENSEX': '^BSESN',
        'GOLD': 'GC=F',
      };

      final Map<String, String> symbolToLabel = {
        for (final e in symbols.entries) e.value: e.key,
      };

      final Map<String, MarketData> newData = {};

      String _cors(String url) => kIsWeb ? 'https://cors.isomorphic-git.org/' + url : url;

      // If running on web and a Twelve Data API key is supplied via --dart-define,
      // prefer it because it supports browser CORS reliably.
      const tdKey = String.fromEnvironment('TWELVEDATA_API_KEY', defaultValue: '');
      final tdSymbolsCsv = const String.fromEnvironment(
        'TWELVEDATA_SYMBOLS',
        defaultValue: 'NSE:NIFTY_50,NSE:BANKNIFTY,BSE:SENSEX,COMMODITY:GOLD',
      );

      // Try Twelve Data on web when key is available
      if (kIsWeb && tdKey.isNotEmpty) {
        try {
          final items = <String, String>{
            // You can override via --dart-define=TWELVEDATA_SYMBOLS=LABEL:SYMBOL,...
            'NIFTY 50': 'NSE:NIFTY_50',
            'BANKNIFTY': 'NSE:BANKNIFTY',
            'SENSEX': 'BSE:SENSEX',
            'GOLD': 'XAU/USD',
          };
          // Parse overrides if provided
          if (tdSymbolsCsv.isNotEmpty) {
            for (final raw in tdSymbolsCsv.split(',')) {
              final r = raw.trim();
              if (r.isEmpty) continue;
              final parts = r.split(':');
              if (parts.length >= 2) {
                final label = parts.first.trim();
                final symbol = parts.sublist(1).join(':').trim();
                if (label.isNotEmpty && symbol.isNotEmpty) {
                  items[label] = symbol;
                }
              }
            }
          }
          await _fetchTwelveData(items, tdKey, newData);
        } catch (e) {
          debugPrint('Twelve Data fetch failed: $e');
        }
      }

      // 1) Quotes (Yahoo)
      final symbolsCsv = symbols.values.join(',');
      try {
        final quoteUrl = Uri.parse(
          _cors('https://query1.finance.yahoo.com/v7/finance/quote?symbols=' + symbolsCsv),
        );
        final res = await http.get(quoteUrl);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final results = (body['quoteResponse']?['result'] as List?) ?? const [];
          for (final item in results) {
            final map = item as Map<String, dynamic>;
            final sym = map['symbol'] as String?;
            if (sym == null) continue;
            final label = symbolToLabel[sym] ?? sym;
            final price = (map['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
            final change = (map['regularMarketChange'] as num?)?.toDouble() ?? 0.0;
            final changePercent = (map['regularMarketChangePercent'] as num?)?.toDouble() ?? 0.0;
            newData[label] = MarketData(
              symbol: label,
              price: price,
              change: change,
              changePercent: changePercent,
              chartData: const [],
            );
          }
        }
      } catch (e) {
        debugPrint('Quote fetch failed: $e');
      }

      // 2) Small sparkline per symbol (chart endpoint)
      for (final entry in symbols.entries) {
        final label = entry.key;
        final symbol = entry.value;
        try {
          final url = Uri.parse(
            _cors('https://query1.finance.yahoo.com/v8/finance/chart/$symbol?range=1d&interval=5m'),
          );
          final response = await http.get(url);
          if (response.statusCode != 200) continue;
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final results = (json['chart']?['result'] as List?) ?? const [];
          if (results.isEmpty) continue;
          final result = results.first as Map<String, dynamic>;
          final indicators = (result['indicators'] ?? const {}) as Map<String, dynamic>;
          final quotes = (indicators['quote'] as List?) ?? const [];
          final quote = quotes.isNotEmpty ? quotes.first as Map<String, dynamic> : const {};
          final close = (quote['close'] as List?)?.whereType<num>().map((n) => n.toDouble()).toList() ?? const <double>[];
          if (close.isNotEmpty) {
            final trimmed = close.length > 30 ? close.sublist(close.length - 30) : close;
            final existing = newData[label];
            if (existing != null) {
              newData[label] = MarketData(
                symbol: existing.symbol,
                price: existing.price,
                change: existing.change,
                changePercent: existing.changePercent,
                chartData: trimmed,
              );
            } else {
              newData[label] = MarketData(
                symbol: label,
                price: close.last,
                change: 0,
                changePercent: 0,
                chartData: trimmed,
              );
            }
          }
        } catch (e) {
          debugPrint('Chart fetch failed for $label: $e');
        }
      }

      if (!mounted) return;

      setState(() {
        _marketData = newData;
        _loadingMarketData = false;
        _marketDataError = newData.isEmpty
            ? 'Unable to load market data'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMarketData = false;
        _marketDataError = 'Network error: $e';
      });
    }
  }

  Future<void> _fetchTwelveData(
    Map<String, String> labelToSymbol,
    String apiKey,
    Map<String, MarketData> out,
  ) async {
    for (final entry in labelToSymbol.entries) {
      final label = entry.key;
      final symbol = Uri.encodeQueryComponent(entry.value);
      try {
        final uri = Uri.parse(
          'https://api.twelvedata.com/time_series?symbol=$symbol&interval=5min&outputsize=30&apikey=$apiKey',
        );
        final res = await http.get(uri);
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final values = (json['values'] as List?) ?? const [];
        if (values.isEmpty) continue;
        final closes = <double>[];
        for (final v in values) {
          final m = v as Map<String, dynamic>;
          final c = double.tryParse(m['close']?.toString() ?? '');
          if (c != null) closes.add(c);
        }
        if (closes.isEmpty) continue;
        // Twelve Data returns newest first
        final price = closes.first;
        final prev = closes.length > 1 ? closes[1] : price;
        final change = price - prev;
        final changePercent = prev != 0 ? (change / prev) * 100 : 0.0;
        final chart = closes.reversed.take(30).toList();
        out[label] = MarketData(
          symbol: label,
          price: price,
          change: change,
          changePercent: changePercent,
          chartData: chart,
        );
      } catch (e) {
        debugPrint('TD error for $label: $e');
      }
    }
  }

  void _startMarketDataUpdates() {
    _marketDataTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _loadMarketData(silently: true);
    });
  }

  void _startAdviceLatestUpdates() {
    _adviceLatestTimer?.cancel();
    _adviceLatestTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      try {
        await _loadAdviceV2Latest();
      } catch (_) {}
    });
  }

  // Helper: mapping of label -> Yahoo symbol
  static const Map<String, String> _labelToYahoo = {
    'NIFTY 50': '^NSEI',
    'BANKNIFTY': '^NSEBANK',
    'SENSEX': '^BSESN',
    'GOLD': 'GC=F',
  };

  Future<void> _saveAck(String key, String message) async {
    _acknowledgedMessages[key] = message;
    _refreshUnreadIndicators(skipSetState: true);
    if (mounted) {
      setState(() {});
    }
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> map = {};
    final current = prefs.getString('segment_ack_v1');
    if (current != null && current.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(current) as Map);
      } catch (_) {}
    }
    map[key] = message;
    await prefs.setString('segment_ack_v1', jsonEncode(map));
  }

  Future<void> _saveAdviceV2Ack(String category, String id) async {
    _ackAdviceV2Ids[category] = id;
    _refreshUnreadIndicators(skipSetState: true);
    if (mounted) setState(() {});
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> map = {};
    final current = prefs.getString('advice_v2_seen_ids_v1');
    if (current != null && current.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(current) as Map);
      } catch (_) {}
    }
    map[category] = id;
    await prefs.setString('advice_v2_seen_ids_v1', jsonEncode(map));
  }

  Future<void> _launchSupportChat() async {
    final uris = SupportConfig.whatsappLaunchOrder;
    if (uris.isEmpty) {
      _showSnack('Support chat is currently unavailable.');
      return;
    }
    for (final uri in uris) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) {
          return;
        }
      } catch (_) {
        // Try next URI if the current one fails.
      }
    }
    if (!mounted) {
      return;
    }
    _showSnack('Unable to open WhatsApp right now.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Use custom asset icons for the home quick actions
    const iconAssets = {
      'stocks': 'assets/icons/stock.png',
      'future': 'assets/icons/future.png',
      'options': 'assets/icons/options.png',
      'commodity': 'assets/icons/stock-market.png',
    };
    final items = _segmentDescriptors
        .map(
          (descriptor) => _HomeItem(
            title: descriptor.title,
            icon: descriptor.icon,
            iconAsset: iconAssets[descriptor.key],
            segmentKey: descriptor.key,
            backgroundColor: _segmentBackgroundColor,
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _segmentBackgroundColor,
        title: Image.asset(
          'assets/app_icon/logo.png',
          height: 28,
          fit: BoxFit.contain,
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(color: _segmentBackgroundColor),
        ),
        centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Daily Tip',
              icon: const Icon(Icons.lightbulb_outline),
              onPressed: () {
                Navigator.of(context).push(fadeRoute(const DailyTipPage()));
              },
            ),
          ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final itemCount = items.length;
          // Add more gap so icons align nicely on mobile
          const double baseGap = 18.0;
          final gap = itemCount > 1 ? baseGap : 0.0;
          final availableRowWidth = (width - 32).clamp(0.0, 520.0);
          final rawDiameter = itemCount > 0
              ? (availableRowWidth - gap * (itemCount - 1)) / itemCount
              : 0.0;
          double circleDiameter;
          if (rawDiameter.isFinite && rawDiameter > 0) {
            circleDiameter = rawDiameter.clamp(50.0, 66.0);
            if (rawDiameter < 42.0) {
              circleDiameter = rawDiameter;
            }
          } else if (availableRowWidth > 0 && itemCount > 0) {
            circleDiameter = availableRowWidth / itemCount;
          } else {
            circleDiameter = 52.0;
          }
          if (!circleDiameter.isFinite || circleDiameter <= 0) {
            circleDiameter = 52.0;
          }
          final rowWidth = itemCount > 0
              ? circleDiameter * itemCount + gap * (itemCount - 1)
              : circleDiameter;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.wait<void>([
                  _loadSegments(silently: true),
                  _loadGallery(silently: true),
                  _loadAdviceV2Latest(),
                ]);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1) Graphs on top (indices)
                      const _MarketDataSection(),
                      const SizedBox(height: 16),

                      // Greeting removed as per request

                    if (_segmentsError != null) ...[
                      Card(
                        color: scheme.errorContainer.withValues(alpha: 0.4),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: scheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _segmentsError!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_loadingSegments) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 12),
                    ],
                        // 2) Quick action icons
                        Center(
                          child: SizedBox(
                            width: rowWidth,
                            child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) SizedBox(width: gap),
                              SizedBox(
                                width: circleDiameter,
                                child: _HomeCircleTile(
                                  title: items[i].title,
                                  icon: items[i].icon,
                                  iconAsset: items[i].iconAsset,
                                  backgroundColor: items[i]
                                      .backgroundColor, // Use backgroundColor
                                  diameter: circleDiameter,
                                  hasNotification: _isSegmentUnread(
                                        items[i].segmentKey,
                                      ) ||
                                      _isAdviceV2KeyUnread(items[i].segmentKey),
                                  onTap: () => _handleSegmentTap(items[i]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                      const SizedBox(height: 16),
                        // 3) Ads slider (original bundled videos)
                        const SizedBox(height: 16),
                        _AdsSlider(
                          assetPaths: const [
                            'assets/add/1.mp4',
                            'assets/add/2.mp4',
                            'assets/add/3.mp4',
                            'assets/add/4.mp4',
                            'assets/add/5.mp4',
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 4) Latest Updates gallery (clean image-only slider)
                        _GallerySection(
                          images: _galleryImages,
                          loading: _loadingGallery,
                          error: _galleryError,
                          onRetry: () {
                            _loadGallery();
                          },
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: _SupportChatButton(
        onTap: _launchSupportChat,
        hasUnread: _hasUnreadSegments,
        pulse: _supportPulse,
        offset: _supportNudge,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        selectedItemColor: _segmentBackgroundColor,
        unselectedItemColor: Colors.black54,
        onTap: (index) async {
          if (index == 1) {
            await Navigator.of(context).push(
              fadeRoute(ReferralEarningsPage(session: _session)),
            );
          } else if (index == 2) {
            await Navigator.of(context).push(
              fadeRoute(
                WalletScreen(
                  name: _session.user.name,
                  email: _session.user.email,
                  phone: _session.user.phone,
                  token: _accessToken,
                ),
              ),
            );
          } else if (index == 3) {
            await Navigator.of(context).push(
              fadeRoute(ProfilePage(session: _session)),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.card_giftcard_outlined),
            label: 'Referral',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Wallet',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _SegmentDescriptor {
  final String key;
  final String title;
  final IconData icon;
  final _SegmentTone tone;

  const _SegmentDescriptor({
    required this.key,
    required this.title,
    required this.icon,
    required this.tone,
  });
}

enum _SegmentTone { primary, secondary }

class _SupportChatButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool hasUnread;
  final Animation<double> pulse;
  final Animation<Offset> offset;

  const _SupportChatButton({
    required this.onTap,
    required this.hasUnread,
    required this.pulse,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    const double size = 70;

    return SlideTransition(
      position: offset,
      child: ScaleTransition(
        scale: pulse,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Image.asset(
                      'assets/help-icon.png',
                      fit: BoxFit.contain,
                      width: size - 28,
                      height: size - 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Removed legacy WhatsApp glyph (was using FontAwesome). We now use
// the bundled asset 'assets/help-icon.png' directly in the FAB.

class _HomeItem {
  final String title;
  final IconData? icon;
  final String? iconAsset;
  final String segmentKey;
  final Color backgroundColor;

  const _HomeItem({
    required this.title,
    this.icon,
    this.iconAsset,
    required this.segmentKey,
    required this.backgroundColor,
  });
}

/// Circle tile with bigger inner icon and smaller label.
class _HomeCircleTile extends StatefulWidget {
  final String title;
  final IconData? icon;
  final String? iconAsset;
  final Color backgroundColor;
  final VoidCallback onTap;
  final double diameter;
  final bool hasNotification;

  const _HomeCircleTile({
    required this.title,
    this.icon,
    this.iconAsset,
    required this.backgroundColor,
    required this.onTap,
    required this.diameter,
    this.hasNotification = false,
  });

  @override
  State<_HomeCircleTile> createState() => _HomeCircleTileState();
}

class _HomeCircleTileState extends State<_HomeCircleTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title;
    final iconData = widget.icon;
    final iconAsset = widget.iconAsset;
    final backgroundColor =
        widget.backgroundColor; // Use single background color
    final onTap = widget.onTap;
    final diameter = widget.diameter;
    final hasNotification = widget.hasNotification;

    // sizing above
    final baseLabelStyle =
        theme.textTheme.labelMedium ??
        theme.textTheme.bodySmall ??
        const TextStyle(fontSize: 12);
    final baseFontSize = baseLabelStyle.fontSize ?? 12.0;

    // ? slightly smaller, and cap tightly so it never grows too big
    final scaledFontSize = (baseFontSize * (diameter / 64.0)).clamp(9.0, 11.0);

    final labelStyle = baseLabelStyle.copyWith(
      fontSize: scaledFontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1, // a touch tighter
    );

    // Keep icons small and crisp (slightly larger)
    // Increase logo/image size inside the circular icon
    final iconSize = (diameter * 0.48).clamp(20.0, 36.0);

    final baseScale = hasNotification ? 1.02 : 1.0;
    final hoverScale = hasNotification ? 0.03 : 0.04;
    final scale = _hovered ? baseScale + hoverScale : baseScale;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: SizedBox(
          width: diameter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: diameter,
                height: diameter,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    customBorder: const CircleBorder(),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF1F2F4), // light neutral circle to lift logos on white bg
                      border: Border.all(color: Colors.black12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                          if (iconAsset != null)
                            Image.asset(
                              iconAsset,
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                            )
                          else
                            Icon(
                              iconData ?? Icons.circle,
                              size: iconSize,
                              color: backgroundColor,
                            ),
                          if (hasNotification)
                            Positioned(
                              top: diameter * 0.18,
                              right: diameter * 0.18,
                              child: _NotificationBadge(
                                iconColor: backgroundColor,
                              ),
                            ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: labelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge({required this.iconColor, this.backgroundColor});

  final Color iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor;
    if (bg == null) {
      return Icon(Icons.notifications, color: iconColor, size: 18);
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(Icons.notifications, color: iconColor, size: 14),
    );
  }
}

class _DailyTipChip extends StatelessWidget {
  const _DailyTipChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _HomePageState._segmentBackgroundColor,
                _HomePageState._segmentBackgroundColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _HomePageState._segmentBackgroundColor.withValues(
                  alpha: 0.35,
                ),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lightbulb_outline, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'DailyTip',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Blank DailyTip page =====
class DailyTipPage extends StatelessWidget {
  const DailyTipPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF7ECEF), // subtle reddish background
      appBar: AppBar(
        title: const Text('DailyTip'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.secondary],
            ),
          ),
        ),
      ),
      // Blank for now as requested
      body: const SizedBox.shrink(),
    );
  }
}

// ------------------------------ Ads views ---------------------------------

class _AdVideoTile extends StatefulWidget {
  final String assetPath;

  const _AdVideoTile({Key? key, required this.assetPath}) : super(key: key);

  @override
  State<_AdVideoTile> createState() => _AdVideoTileState();
}

class _AdVideoTileState extends State<_AdVideoTile>
    with AutomaticKeepAliveClientMixin<_AdVideoTile> {
  static final Uri _adLandingUri = Uri.parse(
    'https://ekyc.arhamwealth.com/?branchcode=PSS&rmcode=&apcode=',
  );
  VideoPlayerController? _controller;
  bool _failed = false;
  Timer? _initGuard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AdVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _controller?.dispose();
      _controller = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final controller = (widget.assetPath.startsWith('http') ? VideoPlayerController.networkUrl(Uri.parse(widget.assetPath), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)) : VideoPlayerController.asset(widget.assetPath, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
      _initGuard?.cancel();
      unawaited(controller.play());
    } catch (e) {
      debugPrint('Ad asset failed to load ${widget.assetPath}: $e');
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _initGuard?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _openAdLink() async {
    try {
      final launched = await launchUrl(
        _adLandingUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open the offer link.')),
        );
      }
    } catch (e) {
      debugPrint('Failed to launch ad link: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the offer link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller;
    final aspectRatio =
        controller != null &&
            controller.value.isInitialized &&
            controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    const borderRadius = BorderRadius.all(Radius.circular(16));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openAdLink,
        borderRadius: borderRadius,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: controller != null && controller.value.isInitialized
                ? VideoPlayer(controller)
                : (_failed
                    ? const _AdBannerFallback()
                    : const _LoadingAdPlaceholder()),
          ),
        ),
      ),
    );
  }
}

class _LoadingAdPlaceholder extends StatelessWidget {
  const _LoadingAdPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}

// Fallback shown if the ad video cannot be played (e.g. unsupported codec on web)
class _AdBannerFallback extends StatelessWidget {
  const _AdBannerFallback();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Use an existing bundled image as a visual banner
        Image.asset(
          'assets/app_icon/loader.jpg',
          fit: BoxFit.cover,
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Tap to view offer',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GallerySection extends StatelessWidget {
  const _GallerySection({
    required this.images,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<GalleryImage> images;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImages = images.isNotEmpty;
    final errorMessage = error;

    Widget content;
      if (loading && !hasImages) {
        content = const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      } else if (!hasImages && errorMessage != null) {
      content = _GalleryInfoCard(
        icon: Icons.wifi_off,
        message: errorMessage,
        actionLabel: 'Retry',
        onAction: loading ? null : onRetry,
      );
    } else if (!hasImages) {
      content = _GalleryInfoCard(
        icon: Icons.image_outlined,
        message: 'No images available yet.',
        actionLabel: 'Refresh',
        onAction: loading ? null : onRetry,
      );
    } else {
      content = _GallerySlider(images: images);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Latest Update',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (loading && hasImages)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            const Spacer(),
            IconButton(
              onPressed: loading ? null : onRetry,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh images',
            ),
          ],
        ),
        const SizedBox(height: 8),
        content,
        if (errorMessage != null && hasImages)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _GallerySlider extends StatefulWidget {
  const _GallerySlider({required this.images});

  final List<GalleryImage> images;

  @override
  State<_GallerySlider> createState() => _GallerySliderState();
}

class _GallerySliderState extends State<_GallerySlider> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.96);
  }

  @override
  void didUpdateWidget(covariant _GallerySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images.length != widget.images.length) {
      _currentPage = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final image = images[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _GalleryTile(image: image),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (index) {
            final active = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 14 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.image});

  final GalleryImage image;

  double get _aspectRatio {
    final width = image.width;
    final height = image.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Image.network(
          image.url,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryInfoCard extends StatelessWidget {
  const _GalleryInfoCard({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple grid with four market symbol cards (NIFTY, BANKNIFTY, COMMODITY, STOCKS)
class _MarketSymbolsGrid extends StatelessWidget {
  const _MarketSymbolsGrid();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = const [
      _SymbolItem('NIFTY 50', 'assets/symbols/nifty50.png'),
      _SymbolItem('BANKNIFTY', 'assets/symbols/banknifty.png'),
      _SymbolItem('COMMODITY', 'assets/symbols/commodity.png'),
      _SymbolItem('STOCKS', 'assets/symbols/stocks.png'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => _MarketSymbolCard(item: items[index]),
        ),
      ],
    );
  }
}

class _SymbolItem {
  final String label;
  final String asset;
  const _SymbolItem(this.label, this.asset);
}

class _MarketSymbolCard extends StatelessWidget {
  final _SymbolItem item;
  const _MarketSymbolCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            item.asset,
            fit: BoxFit.cover,
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Text(
              item.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketDataSection extends StatelessWidget {
  const _MarketDataSection();

  @override
  Widget build(BuildContext context) {
    final homeState = context.findAncestorStateOfType<_HomePageState>()!;
    final marketData = homeState._marketData;
    final loading = homeState._loadingMarketData;
    final error = homeState._marketDataError;

    // Always show 4 squares; use live data when available otherwise dummy
    List<String> labels = const ['NIFTY 50', 'BANKNIFTY', 'SENSEX', 'GOLD'];
    final rnd = Random(DateTime.now().day);
    List<MarketData> items = labels.map((label) {
      final d = marketData[label];
      if (d != null && d.price > 0) return d;
      // dummy data
      final base = switch (label) {
        'NIFTY 50' => 24000.0,
        'BANKNIFTY' => 51000.0,
        'SENSEX' => 79500.0,
        _ => 62000.0,
      };
      final change = (rnd.nextDouble() - 0.5) * (label == 'GOLD' ? 200 : 400);
      final changePct = (change / base) * 100;
      final chart = List<double>.generate(30, (i) {
        final noise = (rnd.nextDouble() - 0.5) * (label == 'GOLD' ? 30 : 60);
        return base + i * (change / 30) + noise;
      });
      return MarketData(
        symbol: label,
        price: base + change,
        change: change,
        changePercent: changePct,
        chartData: chart,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
              // Make tiles a little larger/taller
              childAspectRatio: 1.2,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _MarketDataCard(
              data: item,
              onTap: () => Navigator.of(context).push(
                fadeRoute(_MarketDetailPage(label: item.symbol)),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MarketDataCard extends StatelessWidget {
  final MarketData data;
  final VoidCallback? onTap;

  const _MarketDataCard({required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPositive = data.change >= 0;
    final color = isPositive ? Colors.green : Colors.red;

      return Card(
        elevation: 2,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.symbol,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Rs ${data.price.toStringAsFixed(2)}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Row(
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  '${isPositive ? '+' : ''}${data.change.toStringAsFixed(2)} (${data.changePercent.toStringAsFixed(2)}%)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: _SimpleChart(data: data.chartData, color: color),
              ),
            ],
          ),
        ),
        ),
      );
  }
}

class _SimpleChart extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _SimpleChart({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    // Always render a graph. If real series is empty, draw a smooth dummy series
    // with visible variation so it never looks like a flat line.
    final series = (data.isNotEmpty)
        ? data
        : List<double>.generate(
            40,
            (i) => 100 + i * 0.8 + sin(i / 3.0) * 8 + cos(i / 5.0) * 3,
          );

    double dataMin = series.first;
    double dataMax = series.first;
    for (final v in series) {
      if (v < dataMin) dataMin = v;
      if (v > dataMax) dataMax = v;
    }
    double dataRange = dataMax - dataMin;
    // Ensure some vertical spread even for nearly flat series
    if (dataRange < 1e-6) {
      dataMin -= 1.0;
      dataMax += 1.0;
      dataRange = dataMax - dataMin;
    }

      return CustomPaint(
        painter: _ChartPainter(
          data: series,
          color: color,
          min: dataMin,
          max: dataMax,
          range: dataRange,
        ),
      );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double min;
  final double max;
  final double range;

  _ChartPainter({
    required this.data,
    required this.color,
    required this.min,
    required this.max,
    required this.range,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || range == 0) return;
    // Ensure white background for chart area
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    // background grid (subtle)
    final gridPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    final gridLines = 3;
    for (int i = 1; i <= gridLines; i++) {
      final dy = size.height * (i / (gridLines + 1));
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    // Smooth path
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final width = size.width / (data.length - 1);
    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = i * width;
      final y = size.height - ((data[i] - min) / range) * size.height;
      points.add(Offset(x, y));
    }

    Path linePath = Path();
    if (points.isNotEmpty) {
      linePath.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        final p0 = points[i - 1];
        final p1 = points[i];
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        if (i == 1) {
          linePath.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
        } else {
          final prev = points[i - 2];
          final prevMid = Offset((prev.dx + p0.dx) / 2, (prev.dy + p0.dy) / 2);
          linePath.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
        }
        if (i == points.length - 1) {
          linePath.quadraticBezierTo(p1.dx, p1.dy, p1.dx, p1.dy);
        }
      }
    }

    // Fill under curve
    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.05)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final fillPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Stroke on top
    canvas.drawPath(linePath, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ============================= Details Page ================================
class _MarketDetailPage extends StatefulWidget {
  final String label; // e.g., NIFTY 50

  const _MarketDetailPage({required this.label});

  @override
  State<_MarketDetailPage> createState() => _MarketDetailPageState();
}

class _MarketDetailPageState extends State<_MarketDetailPage> {
  String _range = '3mo';
  bool _loading = true;
  String? _error;
  List<double> _data = const [];
  double _price = 0;
  double _change = 0;
  double _changePct = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final label = widget.label;
      final symbol = _HomePageState._labelToYahoo[label] ?? label;
      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?range=$_range&interval=${_intervalForRange(_range)}');
      final res = await http.get(url);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (json['chart']?['result'] as List?) ?? const [];
      if (results.isEmpty) throw Exception('No result');
      final result = results.first as Map<String, dynamic>;
      final indicators = (result['indicators'] ?? const {}) as Map<String, dynamic>;
      final quotes = (indicators['quote'] as List?) ?? const [];
      final quote = quotes.isNotEmpty ? quotes.first as Map<String, dynamic> : const {};
      final close = (quote['close'] as List?)?.whereType<num>().map((n) => n.toDouble()).toList() ?? const <double>[];
      if (close.isEmpty) throw Exception('No series');
      final price = close.last;
      final prev = close.length > 1 ? close[close.length - 2] : price;
      final change = price - prev;
      final changePct = prev != 0 ? (change / prev) * 100 : 0.0;
      setState(() {
        _data = close.length > 80 ? close.sublist(close.length - 80) : close;
        _price = price;
        _change = change;
        _changePct = changePct;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unable to load data';
        _loading = false;
        // fallback with smooth dummy
        _data = List<double>.generate(80, (i) => 100 + i * 0.5 + sin(i / 4) * 3);
        _price = _data.last;
        _change = _data.last - _data[_data.length - 2];
        _changePct = _change / _data[_data.length - 2] * 100;
      });
    }
  }

  String _intervalForRange(String r) {
    switch (r) {
      case '1d':
        return '5m';
      case '5d':
        return '15m';
      case '1mo':
        return '1d';
      case '3mo':
        return '1d';
      case '6mo':
        return '1d';
      case '1y':
        return '1wk';
    }
    return '1d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = const Color(0xFF1B7B5E);
    final pos = _change >= 0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.label)),
      backgroundColor: const Color(0xFFF7ECEF),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Row(
                children: [
                  Text('₹${_price.toStringAsFixed(2)}',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (pos ? Colors.green : Colors.red).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${pos ? '+' : ''}${_change.toStringAsFixed(2)} (${_changePct.toStringAsFixed(2)}%)',
                    style: theme.textTheme.labelLarge?.copyWith(color: pos ? Colors.green : Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _data.isEmpty
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                          : _SimpleChart(data: _data, color: green),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in const ['1d', '5d', '1mo', '3mo', '6mo', '1y'])
                  ChoiceChip(
                    label: Text(r),
                    selected: _range == r,
                    onSelected: (v) {
                      if (!v) return;
                      setState(() => _range = r);
                      _fetch();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promo image slider (gradient cards with CTA), inspired by provided mock
// ---------------------------------------------------------------------------

// Removed previous promo slider (gradient image cards) per request

class _AdsSlider extends StatefulWidget {
  final List<String> assetPaths;

  const _AdsSlider({Key? key, required this.assetPaths}) : super(key: key);

  @override
  State<_AdsSlider> createState() => _AdsSliderState();
}

class _AdsSliderState extends State<_AdsSlider> {
  late final PageController _pageController;
  int _index = 0;
  Timer? _timer;
  List<String> _validPaths = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.95);
    _prepareAssets();
  }

  @override
  void didUpdateWidget(covariant _AdsSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPaths.join('|') != widget.assetPaths.join('|')) {
      _timer?.cancel();
      _prepareAssets();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _prepareAssets() async {
    final deduped = widget.assetPaths.toSet().toList();
    if (!mounted) return;
    setState(() {
      _validPaths = deduped.isEmpty ? widget.assetPaths : deduped;
      _index = 0;
      _ready = true;
    });
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer?.cancel();
    if (_validPaths.length <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_pageController.hasClients) return;
        final current = _pageController.page?.round() ?? _index;
        final lastIndex = _validPaths.length - 1;
        if (current >= lastIndex) {
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
          );
        } else {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final paths = _validPaths;
    final dotActive = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            itemCount: paths.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _AdVideoTile(key: ValueKey(paths[i]), assetPath: paths[i]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(paths.length, (i) {
            final active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? dotActive : dotActive.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        ),
      ],
    );
  }
}


