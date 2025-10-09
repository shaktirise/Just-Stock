import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'package:newjuststock/wallet/services/wallet_service.dart';
 

class WalletScreen extends StatefulWidget {
  final String name;
  final String email;
  final String? phone;
  final String? token;

  const WalletScreen({
    super.key,
    required this.name,
    required this.email,
    this.phone,
    this.token,
  });

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Razorpay? _razorpay;
  bool get _supportsRazorpay =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  WalletBalance? _balance;
  bool _loadingBalance = true;
  bool _creatingOrder = false;
  bool _verifyingTopUp = false;
  bool _debiting = false;
  String? _errorMessage;
  WalletOrder? _pendingOrder;
  int? _pendingOrderAmountInRupees;

  @override
  void initState() {
    super.initState();
    if (_supportsRazorpay) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnack('Razorpay checkout is only supported on Android and iOS builds.');
      });
    }
    _loadBalance();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  

  Future<void> _loadBalance({bool silently = false}) async {
    if (!silently) {
      setState(() {
        _loadingBalance = true;
        _errorMessage = null;
      });
    }

    final result = await WalletService.fetchBalance(token: widget.token);
    if (!mounted) return;

    if (result.unauthorized) {
      setState(() {
        _loadingBalance = false;
        _errorMessage = 'Session expired. Please log in again.';
        _balance = null;
      });
      _showSnack('Session expired. Please log in again.');
      return;
    }

    if (result.ok) {
      setState(() {
        _balance = result.data;
        _loadingBalance = false;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _loadingBalance = false;
        _errorMessage = result.message;
      });
      _showSnack(result.message);
    }
  }

  Future<void> _promptTopUp() async {
    if (!_supportsRazorpay) {
      _showSnack('Razorpay checkout is only supported on Android and iOS builds.');
      return;
    }
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Money'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount in ₹',
              hintText: 'Enter amount',
              helperText: 'Minimum ₹1000',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  ScaffoldMessenger.of(context)
                    ..removeCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Please enter an amount.')),
                    );
                  return;
                }
                final parsed = int.tryParse(raw);
                if (parsed == null || parsed <= 0) {
                  ScaffoldMessenger.of(context)
                    ..removeCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter a valid amount greater than zero.',
                        ),
                      ),
                    );
                  return;
                }
                Navigator.of(context).pop(parsed);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted || amount == null) return;
    await _startTopUp(amount);
  }

  Future<void> _startTopUp(int amountInRupees) async {
    setState(() {
      _creatingOrder = true;
    });

    final result = await WalletService.createTopUpOrder(
      amountInRupees: amountInRupees,
      token: widget.token,
    );

    if (!mounted) return;

    setState(() {
      _creatingOrder = false;
    });

    if (!result.ok || result.data == null) {
      _showSnack(result.message);
      return;
    }

    _pendingOrder = result.data;
    _pendingOrderAmountInRupees = amountInRupees;
    _openRazorpayCheckout(order: result.data!, amountInRupees: amountInRupees);
  }

  void _openRazorpayCheckout({
    required WalletOrder order,
    required int amountInRupees,
  }) {
    final options = {
      'key': order.key,
      'amount': order.amount, // amount is already in paise from backend
      'currency': order.currency,
      'order_id': order.orderId,
      'name': 'JustStock Wallet',
      'description': 'Top-up ₹$amountInRupees',
      'prefill': {
        'contact': widget.phone ?? '',
        'email': widget.email,
      },
      'theme': {
        'color': '#FFD200',
      },
    };

    final razorpay = _razorpay;
    if (razorpay == null) {
      _showSnack('Razorpay checkout is only supported on Android and iOS builds.');
      return;
    }
    try {
      razorpay.open(options);
    } catch (e) {
      _showSnack('Unable to launch payment: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (_pendingOrder == null) {
      _showSnack('Payment successful but order context missing.');
      return;
    }
    _verifyTopUp(
      orderId: response.orderId ?? _pendingOrder!.orderId,
      paymentId: response.paymentId ?? '',
      signature: response.signature ?? '',
      amountInRupees:
          _pendingOrderAmountInRupees ?? (_pendingOrder!.amount / 100).round(),
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    final msg = response.message?.isNotEmpty == true
        ? response.message!
        : 'Payment failed. Please try again.';
    _showSnack(msg);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _showSnack('External wallet selected: ${response.walletName}');
  }

  Future<void> _verifyTopUp({
    required String orderId,
    required String paymentId,
    required String signature,
    required int amountInRupees,
  }) async {
    if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
      _showSnack('Missing payment confirmation details.');
      return;
    }
    if (amountInRupees <= 0) {
      _showSnack('Unable to verify payment amount.');
      return;
    }

    setState(() {
      _verifyingTopUp = true;
    });

    final result = await WalletService.verifyTopUp(
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: signature,
      amountInRupees: amountInRupees,
      token: widget.token,
    );

    if (!mounted) return;

    setState(() {
      _verifyingTopUp = false;
    });

    if (result.ok) {
      setState(() {
        _pendingOrder = null;
        _pendingOrderAmountInRupees = null;
      });
      _showSnack('Payment verified successfully.');
      await _loadBalance(silently: true);
    } else {
      _showSnack(result.message);
    }
  }

  Future<void> _debitWallet({
    int amountInRupees = 50,
    String note = 'Sample purchase',
  }) async {
    setState(() {
      _debiting = true;
    });

    final result = await WalletService.debit(
      amountInRupees: amountInRupees,
      note: note,
      token: widget.token,
    );

    if (!mounted) return;

    setState(() {
      _debiting = false;
    });

    if (result.ok && result.data != null) {
      final receipt = result.data!;
      final total = receipt.debitedRupees.toStringAsFixed(2);
      final base = receipt.baseAmountRupees.toStringAsFixed(2);
      final gst = receipt.gstAmountRupees.toStringAsFixed(2);
      final noteSuffix =
          receipt.note != null && receipt.note!.trim().isNotEmpty
              ? ' (${receipt.note})'
              : '';
      _showSnack('₹$total debited (₹$base + ₹$gst GST)$noteSuffix.');
      await _loadBalance(silently: true);
    } else {
      _showSnack(result.message);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final balanceText = _balance != null
        ? '₹${(_balance!.balancePaise / 100).toStringAsFixed(2)}'
        : '₹0.00';

    final refreshing = _loadingBalance || _verifyingTopUp;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        backgroundColor: scheme.secondary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_verifyingTopUp || _creatingOrder || _debiting)
            LinearProgressIndicator(
              value: null,
              minHeight: 2,
              backgroundColor: scheme.primary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadBalance(silently: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Balance',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (refreshing)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            Text(
                              balanceText,
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _creatingOrder ? null : _promptTopUp,
                    icon: const Icon(Icons.add_circle_outline),
                    label: _creatingOrder
                        ? const Text('Creating order...')
                        : const Text('Add Money'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _debiting ? null : () => _debitWallet(),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: _debiting
                        ? const Text('Processing...')
                        : const Text('Purchase for ₹50'),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    color: scheme.primaryContainer.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How it works',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add money using Razorpay test mode. After successful payment, the transaction is verified and your balance refreshes automatically.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'For production, update the Razorpay key and prefill details with live credentials.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
