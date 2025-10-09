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

  bool get _canShareReferral =>
      _referralLink != null || _referralCode != null;

  String? get _shareTemplate => _config?.shareUrlTemplate;

  Future<void> _refreshSession({bool silent = false}) async {
    if (!silent) {
      setState(() => _refreshing = true);
    }

    final maybeSession = await SessionService.ensureSession();
    if (!mounted) return;
    if (maybeSession == null) {
      if (!silent) {
        setState(() => _refreshing = false);
      }
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
      if (!silent) {
        setState(() => _refreshing = false);
      }
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
      if (!silent) {
        setState(() => _loadingConfig = false);
      }
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
    final message =
        'Join me on JustStock using my referral link: $shareTarget';
    await Share.share(
      message,
      subject: 'JustStock referral',
    );
  }

  Widget _buildAccountHighlightsCard(ColorScheme scheme) {
    final theme = Theme.of(context);
    final referralCode = _referralCode;
    final shareLink = _referralLink;
    final canCopyLink = shareLink != null && shareLink.isNotEmpty;
    final String? shareLinkLabel = canCopyLink ? shareLink : null;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wallet balance',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formattedWalletBalance,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open wallet',
                  onPressed: () => _openWallet(),
                  icon: const Icon(Icons.launch_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: scheme.primary.withValues(alpha: 0.12)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Referral code',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        referralCode ?? 'Not assigned',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  onPressed: referralCode == null
                      ? null
                      : () => _copyValue(
                            referralCode,
                            'Referral code copied',
                          ),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share link',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shareLinkLabel ?? 'Generated after your account is active.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: canCopyLink
                        ? () {
                            final link = shareLinkLabel;
                            if (link == null) return;
                            _copyValue(
                              link,
                              'Referral link copied',
                            );
                          }
                        : null,
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy link',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _canShareReferral ? _shareReferral : null,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share link'),
                ),
                OutlinedButton.icon(
                  onPressed: _openReferralList,
                  icon: const Icon(Icons.people_outline),
                  label: const Text('View list'),
                ),
                OutlinedButton.icon(
                  onPressed: _openReferralTree,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Tree'),
                ),
                OutlinedButton.icon(
                  onPressed: _openReferralEarnings,
                  icon: const Icon(Icons.currency_rupee_outlined),
                  label: const Text('Earnings'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Active referrals: ${_session.user.referralCount}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSection(ThemeData theme) {
    if (_loadingConfig) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Loading referral programme details…',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_configError != null && _configError!.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Referral programme details unavailable',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _configError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      _loadReferralConfigFor(_session, silent: false),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final config = _config;
    if (config == null) {
      return const SizedBox.shrink();
    }

    final levelEntries = config.levelPercentages.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    String? gstDisplay;
    if (config.gstRate != null) {
      final percent = (config.gstRate! * 100).toStringAsFixed(2);
      gstDisplay = '$percent% GST applied on debits';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Referral programme',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (config.minimumActivationAmount != null)
              Text(
                'Minimum activation: ₹ ${config.minimumActivationAmount}',
                style: theme.textTheme.bodyMedium,
              ),
            if (config.minimumTopUpAmount != null)
              Text(
                'Minimum top-up: ₹ ${config.minimumTopUpAmount}',
                style: theme.textTheme.bodyMedium,
              ),
            if (gstDisplay != null)
              Text(
                gstDisplay,
                style: theme.textTheme.bodyMedium,
              ),
            if (config.shareUrlTemplate != null &&
                config.shareUrlTemplate!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Share template:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                config.shareUrlTemplate!,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (levelEntries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Level payouts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
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
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        _initial,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _email,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _phone,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildAccountHighlightsCard(theme.colorScheme),
            const SizedBox(height: 16),
            if (_loadingConfig ||
                _config != null ||
                (_configError != null && _configError!.isNotEmpty)) ...[
              const SizedBox(height: 16),
              _buildConfigSection(theme),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
