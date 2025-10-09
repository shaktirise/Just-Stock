import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/session_service.dart';

class ReferralListPage extends StatefulWidget {
  final AuthSession session;

  const ReferralListPage({super.key, required this.session});

  @override
  State<ReferralListPage> createState() => _ReferralListPageState();
}

class _ReferralListPageState extends State<ReferralListPage> {
  ReferralListResponse? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReferrals();
  }

  Future<void> _loadReferrals() async {
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
    final response = await AuthService.fetchReferrals(
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
    await _loadReferrals();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral List'),
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
                              onPressed: _loadReferrals,
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
                                  Icons.people_outline,
                                  size: 48,
                                  color: theme.colorScheme.secondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No referrals yet',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Share your referral link to start building your network.',
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
                                      'Total referrals',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${data.total}',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Active from latest session: ${widget.session.user.referralCount}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final entry = data.referrals[index - 1];
                          return Card(
                            child: ListTile(
                              title: Text(
                                entry.name.isEmpty ? entry.email : entry.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.email),
                                  if (entry.phone != null &&
                                      entry.phone!.isNotEmpty)
                                    Text(entry.phone!),
                                  if (entry.referralCode != null &&
                                      entry.referralCode!.isNotEmpty)
                                    Text(
                                      'Code: ${entry.referralCode}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  Text(
                                    'Logins: ${entry.loginCount}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: data.referrals.length + 1,
                      ),
      ),
    );
  }
}
