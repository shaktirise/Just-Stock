import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/features/profile/presentation/pages/profile_page.dart';
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

class HomePage extends StatefulWidget {
  final AuthSession session;

  const HomePage({
    super.key,
    required this.session,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AuthSession _session;

  static const List<String> _segmentKeys = [
    'nifty',
    'banknifty',
    'stocks',
    'sensex',
    'commodity',
  ];

  static const Color _segmentBackgroundColor = Color(0xFFF57C00); // Orange shade from screenshot

  static const List<_SegmentDescriptor> _segmentDescriptors = [
    _SegmentDescriptor(
      key: 'nifty',
      title: 'NIFTY',
      icon: Icons.trending_up,
      tone: _SegmentTone.primary,
    ),
    _SegmentDescriptor(
      key: 'banknifty',
      title: 'BANKNIFTY',
      icon: Icons.account_balance,
      tone: _SegmentTone.secondary,
    ),
    _SegmentDescriptor(
      key: 'stocks',
      title: 'STOCKS',
      icon: Icons.auto_graph,
      tone: _SegmentTone.primary,
    ),
    _SegmentDescriptor(
      key: 'sensex',
      title: 'SENSEX',
      icon: Icons.show_chart,
      tone: _SegmentTone.secondary,
    ),
    _SegmentDescriptor(
      key: 'commodity',
      title: 'COMMODITY',
      icon: Icons.analytics_outlined,
      tone: _SegmentTone.primary,
    ),
  ];

  final Map<String, SegmentMessage> _segmentMessages = {};
  final Map<String, String> _acknowledgedMessages = {};
  bool _loadingSegments = false;
  String? _segmentsError;

  List<GalleryImage> _galleryImages = const [];
  bool _loadingGallery = false;
  String? _galleryError;
  late final AnimationController _supportAnimationController;
  late final Animation<double> _supportPulse;
  late final Animation<Offset> _supportNudge;
  bool _hasUnreadSegments = false;

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
    _supportNudge = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.06),
    ).animate(
      CurvedAnimation(
        parent: _supportAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _loadSegments();
    _loadGallery();
    _loadSeenAcks();
  }

  @override
  void dispose() {
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
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const LoginPage()),
      (route) => false,
    );
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
      _segmentKeys,
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

      final missingKeys = _segmentKeys
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
        final missingKeys = _segmentKeys
            .where((key) => !segments.containsKey(key))
            .toList();
        if (missingKeys.isNotEmpty) {
          _showSnack('Some market updates could not be refreshed.');
        }
      }
    }
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
    final hasUnread = _segmentKeys.any(_isSegmentUnread);
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

  // New method to check for admin messages and update the indicator
  Future<void> _handleSegmentTap(_HomeItem item) async {
    final segment = _segmentMessages[item.segmentKey];
    final message = segment?.message.trim() ?? '';
    if (segment == null || message.isEmpty) {
      _showSnack('No update for ${item.title} yet.');
      return;
    }

    final alreadyUnlocked = _acknowledgedMessages[item.segmentKey] == message;
    if (!alreadyUnlocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Unlock ${item.title}?'),
          content: const Text(
            'Unlock this message for Rs 100. Amount will be debited from your wallet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Pay Rs 100'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final result = await WalletService.debit(
        amountInRupees: 100,
        note: 'Unlock ${item.segmentKey} message',
        token: _accessToken,
      );
      if (!result.ok) {
        _showSnack(result.message);
        return;
      }

      await _saveAck(item.segmentKey, message);
    } else {
      _refreshUnreadIndicators(skipSetState: true);
    }

    final label = segment.label.trim().isEmpty ? item.title : segment.label;
    if (!mounted) return;
    await Navigator.of(context).push(
      fadeRoute(
        AdminMessagePage(
          message: AdminMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: label,
            body: message,
            createdAt: segment.updatedAt ?? DateTime.now(),
          ),
        ),
      ),
    );
    if (!mounted) return;
    _refreshUnreadIndicators();
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
    final items = _segmentDescriptors
        .map(
          (descriptor) => _HomeItem(
            title: descriptor.title,
            icon: descriptor.icon,
            segmentKey: descriptor.key,
            backgroundColor: _segmentBackgroundColor, // Use solid orange color
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
          decoration: BoxDecoration(
            color: _segmentBackgroundColor,
          ),
        ),
        centerTitle: false,
        actions: [
          // Removed the bell icon (Icons.notifications_none)
          // Replaced with Wallet icon
          IconButton(
            tooltip: 'Wallet',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () {
              Navigator.of(context).push(
                fadeRoute(
                  WalletScreen(
                    name: _session.user.name,
                    email: _session.user.email,
                    phone: _session.user.phone,
                    token: _accessToken,
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: InkWell(
              onTap: () async {
                final updated = await Navigator.of(context).push<AuthSession?>(
                  fadeRoute(
                    ProfilePage(session: _session),
                  ),
                );
                if (!mounted) return;
                if (updated != null) {
                  setState(() => _session = updated);
                  await SessionService.updateSession(updated);
                } else {
                  await _syncSession(silent: true);
                }
              },
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                foregroundColor: scheme.primary,
                child: Text(_initial),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final itemCount = items.length;
          const double baseGap = 6.0;
          final gap = itemCount > 1 ? baseGap : 0.0;
          final availableRowWidth = (width - 32).clamp(0.0, 520.0);
          final rawDiameter = itemCount > 0
              ? (availableRowWidth - gap * (itemCount - 1)) / itemCount
              : 0.0;
          double circleDiameter;
          if (rawDiameter.isFinite && rawDiameter > 0) {
            circleDiameter = rawDiameter.clamp(42.0, 88.0);
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
                ]);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $_displayName!',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),

                    const SizedBox(height: 20),

                    _DailyTipChip(
                      onTap: () {
                        Navigator.of(
                          context,
                        ).push(fadeRoute(const DailyTipPage()));
                      },
                    ),

                    const SizedBox(height: 28),

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
                                  backgroundColor: items[i].backgroundColor, // Use backgroundColor
                                  diameter: circleDiameter,
                                  hasNotification: _isSegmentUnread(
                                    items[i].segmentKey,
                                  ),
                                  onTap: () => _handleSegmentTap(items[i]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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
                    const SizedBox(height: 24),
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
  final IconData icon;
  final String segmentKey;
  final Color backgroundColor; // Changed to single background color

  const _HomeItem({
    required this.title,
    required this.icon,
    required this.segmentKey,
    required this.backgroundColor,
  });
}

/// Circle tile with bigger inner icon and smaller label.
class _HomeCircleTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color backgroundColor; // Changed to single background color
  final VoidCallback onTap;
  final double diameter;
  final bool hasNotification;

  const _HomeCircleTile({
    required this.title,
    required this.icon,
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
    final icon = widget.icon;
    final backgroundColor = widget.backgroundColor; // Use single background color
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

    // ? make the inner icon a bit smaller so everything breathes
    final iconSize = (diameter * 0.4).clamp(16.0, 36.0); // Increased icon size

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
                        color: backgroundColor,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(icon, size: iconSize, color: Colors.white),
                          if (hasNotification)
                            Positioned(
                              top: diameter * 0.18,
                              right: diameter * 0.18,
                              child: _NotificationBadge(
                                iconColor: Colors.white,
                                backgroundColor: backgroundColor.withValues(alpha: 0.2),
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
      return Icon(
        Icons.notifications,
        color: iconColor,
        size: 18,
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.notifications,
        color: iconColor,
        size: 14,
      ),
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
                color: _HomePageState._segmentBackgroundColor.withValues(alpha: 0.35),
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
      setState(() {
        _failed = false;
      });
      // Start a small timeout guard so we don't show the loading UI forever
      _initGuard?.cancel();
      _initGuard = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        final c = _controller;
        if (c == null || !c.value.isInitialized) {
          setState(() => _failed = true);
        }
      });

      final controller = (widget.assetPath.startsWith('http')
          ? VideoPlayerController.networkUrl(
              Uri.parse(widget.assetPath),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.asset(
              widget.assetPath,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            ));
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
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
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
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

    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        theme.colorScheme.primary.withValues(alpha: 0.12),
        theme.colorScheme.secondary.withValues(alpha: 0.08),
      ],
    );

    const double borderThickness = 10;
    return Container(
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.hardEdge,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(borderThickness),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
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
          ),
        ),
      ),
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
    final placeholderColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: placeholderColor),
            Image.network(
              image.url,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                          : null,
                    ),
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
          ],
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


