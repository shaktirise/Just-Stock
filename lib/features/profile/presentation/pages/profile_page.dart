import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:share_plus/share_plus.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/features/profile/presentation/pages/referral_earnings_page.dart';
import 'package:newjuststock/features/profile/presentation/pages/referral_list_page.dart';
import 'package:newjuststock/features/profile/presentation/pages/referral_tree_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/session_service.dart';
import 'package:newjuststock/wallet/ui/wallet_screen.dart';

class ProfilePage extends StatefulWidget {
  final AuthSession session;

  const ProfilePage({super.key, required this.session});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// Brand + neutrals — high contrast
  static const _kPrimaryYellow = Color(0xFFFFD200);
  // Match Home app bar color
  static const _kAppbarOrange = Color(0xFFF57C00);
  static const _kCard = Colors.white;
  static const _kSurface = Color(0xFFF7F7F9);
  static const _kOutline = Color(0xFFE6E6EA);

  static const _kTextPrimary = Color(0xFF111827);
  static const _kTextSecondary = Color(0xFF4B5563);

  late AuthSession _session;
  bool _refreshing = false;
  ReferralConfig? _config;
  bool _loadingConfig = false;
  String? _configError;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    Future.microtask(() => _refreshSession(silent: true));
  }

  String get _initial =>
      _session.user.name.isNotEmpty ? _session.user.name[0].toUpperCase() : 'U';

  String get _displayName =>
      _session.user.name.isEmpty ? 'JustStock investor' : _session.user.name;

  String get _email =>
      _session.user.email.isEmpty ? 'Email not available' : _session.user.email;

  String get _phone =>
      _session.user.phone?.isNotEmpty == true ? _session.user.phone! : 'Phone not added';

  String? get _referralCode =>
      _session.user.referralCode?.trim().isNotEmpty == true
          ? _session.user.referralCode!.trim().toUpperCase()
          : null;

  String? get _referralLink =>
      _session.user.referralShareLink?.trim().isNotEmpty == true
          ? _session.user.referralShareLink!.trim()
          : null;

  String get _formattedWalletBalance =>
      '₹ ${(_session.user.walletBalancePaise / 100).toStringAsFixed(2)}';

  bool get _canShareReferral => _referralLink != null || _referralCode != null;

  String? get _shareTemplate => _config?.shareUrlTemplate;

  Future<void> _refreshSession({bool silent = false}) async {
    if (!silent) setState(() => _refreshing = true);

    final maybeSession = await SessionService.ensureSession();
    if (!mounted) return;
    if (maybeSession == null) {
      if (!silent) setState(() => _refreshing = false);
      _handleSessionExpired();
      return;
    }

    var session = maybeSession;

    final profileResponse = await AuthService.fetchProfile(
      accessToken: session.accessToken,
      existing: session,
    );
    if (!mounted) return;

    if (profileResponse.isUnauthorized) {
      if (!silent) setState(() => _refreshing = false);
      _handleSessionExpired();
      return;
    }

    if (profileResponse.ok && profileResponse.data != null) {
      session = session.copyWith(user: profileResponse.data!);
      await SessionService.saveSession(session);
    } else if (!silent && profileResponse.message.isNotEmpty) {
      _showSnack(profileResponse.message);
    }

    await _loadReferralConfigFor(session, silent: silent);

    if (!mounted) return;
    if (!silent) {
      setState(() {
        _session = session;
        _refreshing = false;
      });
    } else {
      setState(() => _session = session);
    }
  }

  Future<void> _loadReferralConfigFor(
    AuthSession session, {
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _loadingConfig = true;
        _configError = null;
      });
    }

    final response = await AuthService.fetchReferralConfig(
      accessToken: session.accessToken,
    );
    if (!mounted) return;

    if (response.isUnauthorized) {
      if (!silent) setState(() => _loadingConfig = false);
      _handleSessionExpired();
      return;
    }

    if (response.ok && response.data != null) {
      setState(() {
        _config = response.data;
        _configError = null;
        _loadingConfig = false;
      });
    } else {
      setState(() {
        _configError = response.message;
        _loadingConfig = false;
      });
      if (!silent && response.message.isNotEmpty) {
        _showSnack(response.message);
      }
    }
  }

  void _handleSessionExpired() {
    SessionService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _openReferralList() async {
    await Navigator.of(context).push(
      fadeRoute(ReferralListPage(session: _session)),
    );
    if (!mounted) return;
    await _refreshSession(silent: true);
  }

  Future<void> _openReferralTree() async {
    await Navigator.of(context).push(
      fadeRoute(ReferralTreePage(session: _session)),
    );
    if (!mounted) return;
    await _refreshSession(silent: true);
  }

  Future<void> _openReferralEarnings() async {
    await Navigator.of(context).push(
      fadeRoute(ReferralEarningsPage(session: _session)),
    );
    if (!mounted) return;
    await _refreshSession(silent: true);
  }

  Future<void> _openWallet() async {
    await Navigator.of(context).push(
      fadeRoute(
        WalletScreen(
          name: _session.user.name,
          email: _session.user.email,
          phone: _session.user.phone,
          token: _session.accessToken,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshSession(silent: true);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _copyValue(String value, String message) {
    Clipboard.setData(ClipboardData(text: value));
    _showSnack(message);
  }

  Future<void> _handleLogout() async {
    if (_session.tokens.hasRefreshToken) {
      await AuthService.logout(
        refreshToken: _session.refreshToken,
        accessToken: _session.accessToken,
      );
    }
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _shareReferral() async {
    final code = _referralCode;
    String? shareTarget = _referralLink;
    final template = _shareTemplate;

    if ((shareTarget == null || shareTarget.isEmpty) &&
        template != null &&
        code != null &&
        code.isNotEmpty) {
      shareTarget = template
          .replaceAll('{code}', code)
          .replaceAll('{{code}}', code)
          .replaceAll('%s', code);
    }
    shareTarget ??= code;

    if (shareTarget == null || shareTarget.isEmpty) {
      _showSnack('Referral link not available yet.');
      return;
    }

    final message = 'Join me on JustStock using my referral link: $shareTarget';
    await Share.share(message, subject: 'JustStock referral');
  }

  // ---------- UI PARTS ----------

  Widget _sectionCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kOutline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );
  }

  Widget _profileHeader(ThemeData theme) {
    return _sectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _kPrimaryYellow.withOpacity(.25),
            child: Text(
              _initial,
              style: theme.textTheme.titleLarge?.copyWith(
                color: _kTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _kTextPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    )),
                const SizedBox(height: 2),
                Text(_email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _kTextSecondary,
                      height: 1.3,
                    )),
                Text(_phone,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _kTextSecondary,
                      height: 1.3,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountHighlightsCard(ColorScheme scheme) {
    final theme = Theme.of(context);
    final referralCode = _referralCode;
    final shareLink = _referralLink;
    final canCopyLink = shareLink != null && shareLink.isNotEmpty;
    final String? shareLinkLabel = canCopyLink ? shareLink : null;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wallet balance row
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _kPrimaryYellow.withOpacity(.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.black87),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet balance',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _kTextSecondary,
                        )),
                    const SizedBox(height: 2),
                    Text(_formattedWalletBalance,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: _kTextPrimary,
                          fontWeight: FontWeight.w900,
                        )),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open wallet',
                onPressed: _openWallet,
                icon: const Icon(Icons.launch_rounded),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: _kOutline),
          const SizedBox(height: 14),

          // Referral code
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Referral code',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: _kTextSecondary)),
                    const SizedBox(height: 4),
                    Text(referralCode ?? 'Not assigned',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(
                tooltip: referralCode == null ? 'Not available' : 'Copy code',
                onPressed: referralCode == null
                    ? null
                    : () => _copyValue(referralCode, 'Referral code copied'),
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Share link row
          Container(
            decoration: BoxDecoration(
              color: _kSurface,
              border: Border.all(color: _kOutline),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share link',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: _kTextSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        shareLinkLabel ?? 'Generated after your account is active.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: _kTextPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: canCopyLink ? 'Copy link' : 'Not available',
                  onPressed: canCopyLink
                      ? () => _copyValue(shareLinkLabel!, 'Referral link copied')
                      : null,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Actions — yellow pill buttons (bold)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pillAction(
                icon: Icons.share_rounded,
                label: 'Share link',
                onPressed: _canShareReferral ? _shareReferral : null,
              ),
              _pillAction(
                icon: Icons.people_outline,
                label: 'View list',
                onPressed: _openReferralList,
              ),
              _pillAction(
                icon: Icons.account_tree_outlined,
                label: 'Tree',
                onPressed: _openReferralTree,
              ),
              _pillAction(
                icon: Icons.currency_rupee_outlined,
                label: 'Earnings',
                onPressed: _openReferralEarnings,
              ),
            ],
          ),

          const SizedBox(height: 14),
          Text(
            'Active referrals: ${_session.user.referralCount}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _kTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _configSection(ThemeData theme) {
    if (_loadingConfig) {
      return _sectionCard(
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Loading referral programme details…',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: _kTextPrimary)),
            ),
          ],
        ),
      );
    }

    if (_configError != null && _configError!.isNotEmpty) {
      return _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Referral programme details unavailable',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 8),
            Text(_configError!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _loadReferralConfigFor(_session, silent: false),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }

    final config = _config;
    if (config == null) return const SizedBox.shrink();

    final levelEntries = config.levelPercentages.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    String? gstDisplay;
    if (config.gstRate != null) {
      final percent = (config.gstRate! * 100).toStringAsFixed(2);
      gstDisplay = '$percent% GST applied on debits';
    }

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Referral programme',
              style: theme.textTheme.titleMedium?.copyWith(
                color: _kTextPrimary,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 8),
          if (config.minimumActivationAmount != null)
            Text('Minimum activation: ₹ ${config.minimumActivationAmount}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: _kTextPrimary)),
          if (config.minimumTopUpAmount != null)
            Text('Minimum top-up: ₹ ${config.minimumTopUpAmount}',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: _kTextPrimary)),
          if (gstDisplay != null)
            Text(gstDisplay,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: _kTextSecondary)),
          if (config.shareUrlTemplate != null &&
              config.shareUrlTemplate!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Share template:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _kTextSecondary,
                  fontWeight: FontWeight.w700,
                )),
            Text(config.shareUrlTemplate!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: _kTextPrimary)),
          ],
          if (levelEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Level payouts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _kTextSecondary,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: levelEntries.map((entry) {
                final percentage = entry.value % 1 == 0
                    ? entry.value.toStringAsFixed(0)
                    : entry.value.toStringAsFixed(2);
                return Chip(
                  label: Text('L${entry.key}: $percentage%'),
                  side: const BorderSide(color: _kOutline),
                  backgroundColor: _kSurface,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // Yellow, bold pill action
  Widget _pillAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: _kPrimaryYellow,
        foregroundColor: Colors.black87,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: const StadiumBorder(),
      ),
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: _kAppbarOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : () => _refreshSession(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshSession(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _profileHeader(theme),
            const SizedBox(height: 16),
            _accountHighlightsCard(theme.colorScheme),
            const SizedBox(height: 16),
            if (_loadingConfig ||
                _config != null ||
                (_configError != null && _configError!.isNotEmpty)) ...[
              _configSection(theme),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: _kPrimaryYellow,
                foregroundColor: Colors.black87,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
