import 'package:flutter/material.dart';

import 'package:newjuststock/core/navigation/fade_route.dart';
import 'package:newjuststock/features/auth/presentation/pages/login_page.dart';
import 'package:newjuststock/services/auth_service.dart';
import 'package:newjuststock/services/session_service.dart';

class ReferralTreePage extends StatefulWidget {
  final AuthSession session;

  const ReferralTreePage({super.key, required this.session});

  @override
  State<ReferralTreePage> createState() => _ReferralTreePageState();
}

class _ReferralTreePageState extends State<ReferralTreePage> {
  ReferralTreeResponse? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  Future<void> _loadTree() async {
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
    final response = await AuthService.fetchReferralTree(
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
    await _loadTree();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral Tree'),
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
                              onPressed: _loadTree,
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
                                  Icons.account_tree_outlined,
                                  size: 48,
                                  color: theme.colorScheme.secondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No network data yet',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'As your referrals invite others, you\'ll see each level here.',
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
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: data.levels.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Network depth',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${data.depth} levels returned (max 5)',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Direct referrals from session: ${widget.session.user.referralCount}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final level = data.levels[index - 1];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor:
                                            theme.colorScheme.primary,
                                        child: Text(
                                          level.level.toString(),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Level ${level.level}',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${level.users.length} members',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: level.users.map((user) {
                                      final label = user.name.isNotEmpty
                                          ? user.name
                                          : user.email;
                                      return Chip(
                                        avatar: CircleAvatar(
                                          backgroundColor: theme
                                              .colorScheme.primary
                                              .withValues(alpha: 0.2),
                                          child: Text(
                                            label.isNotEmpty
                                                ? label[0].toUpperCase()
                                                : '?',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        label: Text(label),
                                      );
                                    }).toList(),
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
