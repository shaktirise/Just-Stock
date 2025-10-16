import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/auth_models.dart';
import 'package:newjuststock/services/session_service.dart';

class ReferralEarningsPage extends StatefulWidget {
  final AuthSession session;

  const ReferralEarningsPage({super.key, required this.session});

  @override
  State<ReferralEarningsPage> createState() => _ReferralEarningsPageState();
}

class _ReferralEarningsPageState extends State<ReferralEarningsPage> {
  ReferralEarningsResponse? _data;
  List<ReferralWithdrawalRequestModel> _withdrawals = const [];
  bool _loading = true;
  bool _loadingWithdrawals = true;
  String? _error;

  // Util: render amounts in rupees consistently
  String _rupeesText(int paise) => '₹ ${(paise / 100).toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _loadEarnings();
    _loadWithdrawals();
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

  Future<void> _loadWithdrawals() async {
    setState(() {
      _loadingWithdrawals = true;
    });
    final session = await SessionService.ensureSession();
    if (!mounted) return;
    if (session == null) return _handleSessionExpired();
    final response = await AuthService.fetchReferralWithdrawals(
      accessToken: session.accessToken,
      limit: 20,
    );
    if (!mounted) return;
    if (response.ok && response.data != null) {
      setState(() {
        _withdrawals = response.data!;
        _loadingWithdrawals = false;
      });
    } else if (response.isUnauthorized) {
      _handleSessionExpired();
    } else {
      setState(() {
        _loadingWithdrawals = false;
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
    await _loadWithdrawals();
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
                        itemCount: data.entries.length + 2,
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
                                      _rupeesText(data.totalEarnedPaise),
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
                                    const SizedBox(height: 12),
                                    if (data.totalPendingPaise > 0)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Pending: ${_rupeesText(data.totalPendingPaise)}',
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          FilledButton.icon(
                                            onPressed: _requestWithdrawal,
                                            icon: const Icon(Icons.payments_outlined),
                                            label: const Text('Request Withdrawal'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }
                          if (index == data.entries.length + 1) {
                            return Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Withdrawal Requests',
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                        IconButton(
                                          onPressed: _loadWithdrawals,
                                          icon: const Icon(Icons.refresh),
                                          tooltip: 'Refresh',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (_loadingWithdrawals)
                                      const Center(child: CircularProgressIndicator())
                                    else if (_withdrawals.isEmpty)
                                      Text(
                                        'No withdrawal requests yet.',
                                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                                      )
                                    else
                                      Column(
                                        children: _withdrawals.map((w) {
                                          return ListTile(
                                            dense: true,
                                            leading: const Icon(Icons.receipt_long),
                                            title: Text('${w.status.toUpperCase()} • ₹ ${w.amountRupees.toStringAsFixed(2)}'),
                                            subtitle: Text(
                                              w.createdAt?.toLocal().toString() ?? '',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                            trailing: w.ledgerCount > 0 ? Text('${w.ledgerCount} entries') : null,
                                          );
                                        }).toList(),
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
                                _rupeesText(entry.amountPaise),
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

  Future<void> _requestWithdrawal() async {
    final session = await SessionService.ensureSession();
    if (!mounted) return;
    if (session == null) return _handleSessionExpired();
    final resp = await AuthService.requestReferralWithdrawal(
      accessToken: session.accessToken,
    );
    if (!mounted) return;
    if (resp.ok && resp.data != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Withdrawal request submitted.')),
      );
      await _loadEarnings();
      await _loadWithdrawals();
    } else if (resp.isUnauthorized) {
      _handleSessionExpired();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resp.message)),
      );
    }
  }
}
