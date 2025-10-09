import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/session_service.dart';

class ReferralEarningsPage extends StatefulWidget {
  final AuthSession session;

  const ReferralEarningsPage({super.key, required this.session});

  @override
  State<ReferralEarningsPage> createState() => _ReferralEarningsPageState();
}

class _ReferralEarningsPageState extends State<ReferralEarningsPage> {
  ReferralEarningsResponse? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final session = await SessionService.ensureSession();
    if (!mounted) return;
    if (session == null) {
      _handleSessionExpired();
      return;
    }
    final response = await AuthService.fetchReferralEarnings(
      accessToken: session.accessToken,
    );

    if (!mounted) return;

    if (response.ok && response.data != null) {
      setState(() {
        _data = response.data;
        _loading = false;
        _error = null;
      });
    } else {
      if (response.isUnauthorized) {
        _handleSessionExpired();
        return;
      }
      setState(() {
        _loading = false;
        _error = response.message;
      });
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

  Future<void> _onRefresh() async {
    await _loadEarnings();
  }

  String _formatRupees(int paise) {
    return '₹ ${(paise / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Earnings'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 48,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _loadEarnings,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : (data == null || data.isEmpty)
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.currency_rupee_rounded,
                                  size: 48,
                                  color: theme.colorScheme.secondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No referral earnings yet',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Invite and activate new members to unlock rewards in real time.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: data.entries.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Card(
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total earned',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatRupees(data.totalEarnedPaise),
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'For ${widget.session.user.name.isEmpty ? 'your account' : widget.session.user.name}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final entry = data.entries[index - 1];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primary.withValues(alpha: 0.2),
                                child: const Icon(Icons.currency_rupee),
                              ),
                              title: Text(
                                _formatRupees(entry.amountPaise),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (entry.note.isNotEmpty)
                                    Text(entry.note),
                                  if (entry.createdAt != null)
                                    Text(
                                      entry.createdAt!.toLocal().toString(),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  if (entry.externalReference != null &&
                                      entry.externalReference!.isNotEmpty)
                                    Text(
                                      entry.externalReference!,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
