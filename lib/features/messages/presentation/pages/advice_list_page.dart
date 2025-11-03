import 'package:flutter/material.dart';
import 'package:newjuststock/features/messages/services/advice_service.dart';
import 'package:newjuststock/features/messages/presentation/pages/advice_view_page.dart';
import 'package:newjuststock/wallet/ui/wallet_screen.dart';
import 'package:newjuststock/services/session_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AdviceService.fetchList(category: widget.category, limit: 5);
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
    return '$d $m $y • $hh:$mm';
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
            MaterialPageRoute(builder: (_) => WalletScreen(
              name: session.user.name,
              email: session.user.email,
              phone: session.user.phone,
              token: session.accessToken,
            )),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message.isEmpty ? 'Unlock failed' : res.message)),
        );
      }
      return;
    }

  await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdviceViewPage(detail: res.data!)),
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
            MaterialPageRoute(builder: (_) => WalletScreen(
              name: session.user.name,
              email: session.user.email,
              phone: session.user.phone,
              token: session.accessToken,
            )),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message.isEmpty ? 'Unlock failed' : res.message)),
        );
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdviceViewPage(detail: res.data!)),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: 1 + (_items.isEmpty ? 1 : _items.length),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            leading: const Icon(Icons.flash_on_rounded, color: Colors.orange),
            title: Text('Unlock latest ${widget.title.toLowerCase()}'),
            subtitle: const Text('Instantly unlock the most recent message'),
            trailing: FilledButton(
              onPressed: _unlockLatest,
              child: const Text('Pay latest'),
            ),
          );
        }
        if (_items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('No messages yet. Pull to refresh.')),
          );
        }
        final item = _items[index - 1];
        return ListTile(
          leading: const Icon(Icons.lock_rounded),
          title: Text('Message #${_items.length - (index - 1)}'),
          subtitle: Text(_formatTimestamp(item.createdAt)),
          trailing: FilledButton.tonal(
            onPressed: () => _unlockAndOpen(item),
            child: Text('\u20B9${item.price}'),
          ),
          onTap: null,
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
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            leading: const Icon(Icons.lock_rounded),
                            title: Text('Advice #${_items.length - index}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_formatTimestamp(item.createdAt)),
                                const SizedBox(height: 6),
                                FilledButton.tonal(
                                  onPressed: () => _unlockAndOpen(item),
                                  child: Text('\u20B9${item.price}'),
                                ),
                              ],
                            ),
                            trailing: Text('₹${item.price}'),
                            onTap: () => _unlockAndOpen(item),
                          );
                        },
                      ),
      ),
    );
  }
}
