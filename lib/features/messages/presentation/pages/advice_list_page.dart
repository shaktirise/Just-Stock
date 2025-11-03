import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:newjuststock/features/messages/services/advice_service.dart';
import 'package:newjuststock/features/messages/presentation/pages/advice_view_page.dart';
import 'package:newjuststock/wallet/ui/wallet_screen.dart';
import 'package:newjuststock/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdviceListPage extends StatefulWidget {
  final String category; // expected uppercase canonical: STOCKS/FUTURE/OPTIONS/COMMODITY
  final String title; // display title

  const AdviceListPage({super.key, required this.category, required this.title});

  @override
  State<AdviceListPage> createState() => _AdviceListPageState();
}

class _AdviceListPageState extends State<AdviceListPage> {
  final List<AdviceSummary> _items = [];
  bool _loading = true;
  String? _error;
  final Map<String, AdviceDetail> _unlocked = {}; // id -> detail

  @override
  void initState() {
    super.initState();
    _loadUnlockedCache();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AdviceService.fetchList(category: widget.category, limit: 10);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok && res.data != null) {
        _items
          ..clear()
          ..addAll(res.data!);
      } else {
        _error = res.message;
      }
    });
  }

  String _formatTimestamp(DateTime ts) {
    final local = ts.toLocal();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final m = months[local.month - 1];
    final d = local.day.toString().padLeft(2, '0');
    final y = local.year;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d $m $y · $hh:$mm';
  }

  Future<void> _unlockAndOpen(AdviceSummary summary) async {
    final res = await AdviceService.unlock(adviceId: summary.id);
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      if (res.statusCode == 402) {
        final goTopup = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Insufficient Balance'),
            content: const Text('Your wallet does not have enough balance to unlock this advice. Top up your wallet to continue.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Top up')),
            ],
          ),
        );
        if (goTopup == true && mounted) {
          final session = await SessionService.ensureSession();
          if (!mounted || session == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WalletScreen(
                name: session.user.name,
                email: session.user.email,
                phone: session.user.phone,
                token: session.accessToken,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message.isNotEmpty ? res.message : 'Unlock failed')),
        );
      }
      return;
    }
    await _storeUnlocked(res.data!);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment successful')),
    );
  }

  Future<void> _unlockLatest() async {
    final res = await AdviceService.unlockLatestByCategory(category: widget.category);
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      if (res.statusCode == 402) {
        final goTopup = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Insufficient Balance'),
            content: const Text('Your wallet does not have enough balance to unlock the latest message. Top up your wallet to continue.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Top up')),
            ],
          ),
        );
        if (goTopup == true && mounted) {
          final session = await SessionService.ensureSession();
          if (!mounted || session == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WalletScreen(
                name: session.user.name,
                email: session.user.email,
                phone: session.user.phone,
                token: session.accessToken,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message.isNotEmpty ? res.message : 'Unlock failed')),
        );
      }
      return;
    }
    await _storeUnlocked(res.data!);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment successful')),
    );
  }

  Future<void> _loadUnlockedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('advice_v2_unlocked_cache_v1');
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> map = jsonDecode(raw);
      map.forEach((id, value) {
        if (value is Map) {
          final v = (value as Map).cast<String, dynamic>();
          try {
            _unlocked[id] = AdviceDetail(
              id: id,
              category: (v['category'] ?? '').toString(),
              text: (v['text'] ?? '').toString(),
              createdAt: DateTime.tryParse((v['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0),
              price: (v['price'] is int) ? v['price'] as int : int.tryParse(v['price'].toString()) ?? 0,
              buy: v['buy']?.toString(),
              target: v['target']?.toString(),
              stoploss: v['stoploss']?.toString(),
            );
          } catch (_) {}
        }
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveUnlockedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final e in _unlocked.entries) {
        final d = e.value;
        map[e.key] = {
          'category': d.category,
          'text': d.text,
          'createdAt': d.createdAt.toIso8601String(),
          'price': d.price,
          'buy': d.buy,
          'target': d.target,
          'stoploss': d.stoploss,
        };
      }
      await prefs.setString('advice_v2_unlocked_cache_v1', jsonEncode(map));
    } catch (_) {}
  }

  Future<void> _storeUnlocked(AdviceDetail detail) async {
    setState(() {
      _unlocked[detail.id] = detail;
    });
    await _saveUnlockedCache();
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: 1 + _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                const Icon(Icons.flash_on_rounded, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Unlock latest ${widget.title.toLowerCase()}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(onPressed: _unlockLatest, child: const Text('Pay latest')),
              ],
            ),
          );
        }
        final item = _items[index - 1];
        final unlocked = _unlocked[item.id];
        final text = unlocked?.text ?? 'Message hidden';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Advice #${_items.length - (index - 1)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(unlocked == null ? Icons.lock_rounded : Icons.check_circle, size: 18, color: unlocked == null ? Colors.black45 : Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: unlocked == null ? Colors.black54 : Colors.black87,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_formatTimestamp(item.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (unlocked == null)
                ElevatedButton(
                  onPressed: () => _unlockAndOpen(item),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(92, 40)),
                  child: Text('Pay ₹${item.price}'),
                )
              else
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AdviceViewPage(detail: unlocked)),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('PAID', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _unlockLatest,
            child: const Text('Pay latest'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(child: Text(_error!)),
                      ),
                    ],
                  )
                : (_items.isEmpty)
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(child: Text('No messages yet. Pull to refresh.')),
                          ),
                        ],
                      )
                    : _buildList(),
      ),
    );
  }
}

