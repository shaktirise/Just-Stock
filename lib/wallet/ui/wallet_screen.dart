import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'package:newjuststock/wallet/services/wallet_service.dart';

/// Brand colors to match your screenshot
// Match Home app bar color
const _kAppbarOrange = Color(0xFFF57C00); // header orange (same as home)
const _kPrimaryYellow = Color(0xFFFFD200); // buttons / accents
const _kBalanceBg = Color(0xFFFFF4E5); // light cream for balance card
const _kInfoBg = Color(0xFFFFF8EC); // light cream for info card
const _kTextPrimary = Color(0xFF1F2937); // deep slate (readable)
const _kTextSecondary = Color(0xFF4B5563); // mid slate

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
  String? _errorMessage;
  WalletOrder? _pendingOrder;
  int? _pendingOrderAmountInRupees;
  int? _pendingOrderAmountInPaise;

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
        _showSnack(
          'Razorpay checkout is only supported on Android and iOS builds.',
        );
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
      _showSnack(
        'Razorpay checkout is only supported on Android and iOS builds.',
      );
      return;
    }

    final controller = TextEditingController(text: '0');
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final minTopUp = WalletService.minimumTopUpRupees;
        const quickAmounts = [200, 500, 1000, 2000];
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.account_balance_wallet_rounded, color: _kAppbarOrange),
                  SizedBox(width: 8),
                  Text('Add Money',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (\u20B9)',
                  hintText: 'Enter amount',
                  helperText: 'Minimum \u20B9$minTopUp',
                  prefixIcon: const Icon(Icons.currency_rupee_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _QuickChip(
                    onTap: () => controller.text = '0',
                    label: '\u20B90',
                  ),
                  for (final amount in quickAmounts)
                    _QuickChip(
                      onTap: () => controller.text = '$amount',
                      label: '\u20B9$amount',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kPrimaryYellow,
                    foregroundColor: Colors.black87, // better contrast on yellow
                    minimumSize: const Size.fromHeight(50),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900, // bolder
                      fontSize: 16, // larger
                      letterSpacing: .2,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () {
                    final raw = controller.text.trim();
                    final parsed = int.tryParse(raw);
                    if (raw.isEmpty || parsed == null || parsed <= 0) {
                      ScaffoldMessenger.of(context)
                        ..removeCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid amount greater than zero.'),
                          ),
                        );
                      return;
                    }
                    Navigator.of(context).pop(parsed);
                  },
                  child: const Text('Proceed to Pay'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || amount == null) return;
    await _startTopUp(amount);
  }

  Future<void> _startTopUp(int amountInRupees) async {
    setState(() => _creatingOrder = true);

    final result = await WalletService.createTopUpOrder(
      amountInRupees: amountInRupees,
      token: widget.token,
    );

    if (!mounted) return;

    setState(() => _creatingOrder = false);

    if (!result.ok || result.data == null) {
      _showSnack(result.message);
      return;
    }

    final order = result.data!;
    _pendingOrder = order;
    _pendingOrderAmountInRupees = amountInRupees;
    final resolvedPaise =
        order.resolvedAmountPaise(fallbackRupees: amountInRupees);
    _pendingOrderAmountInPaise = resolvedPaise > 0 ? resolvedPaise : null;
    _openRazorpayCheckout(order: order, amountInRupees: amountInRupees);
  }

  void _openRazorpayCheckout({
    required WalletOrder order,
    required int amountInRupees,
  }) {
    final amountPaise = order.resolvedAmountPaise(
      fallbackRupees: amountInRupees,
    );
    if (amountPaise <= 0) {
      _showSnack('Unable to launch payment: invalid amount.');
      return;
    }
    if (order.key.trim().isEmpty || order.orderId.trim().isEmpty) {
      _showSnack('Unable to launch payment: incomplete order details.');
      return;
    }
    final options = {
      'key': order.key,
      'amount': amountPaise,
      'currency': order.currency.isNotEmpty ? order.currency : 'INR',
      'order_id': order.orderId,
      'name': 'JustStock Wallet',
      'description': 'Top-up \u20B9$amountInRupees',
      'prefill': {
        'contact': widget.phone ?? '',
        'email': widget.email,
        'name': widget.name,
      },
      'theme': {'color': '#FFD200'},
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
    final order = _pendingOrder!;
    final rupees = _pendingOrderAmountInRupees ??
        order.amountRupees ??
        (order.amountPaise > 0 ? order.amountPaise ~/ 100 : 0);
    final paise = _pendingOrderAmountInPaise ??
        order.resolvedAmountPaise(fallbackRupees: rupees);
    _verifyTopUp(
      orderId: response.orderId ?? order.orderId,
      paymentId: response.paymentId ?? '',
      signature: response.signature ?? '',
      amountInRupees: rupees,
      amountInPaise: paise > 0 ? paise : null,
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
    int? amountInPaise,
  }) async {
    if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
      _showSnack('Missing payment confirmation details.');
      return;
    }
    if (amountInRupees <= 0) {
      _showSnack('Unable to verify payment amount.');
      return;
    }
    if (amountInPaise != null && amountInPaise <= 0) {
      _showSnack('Unable to verify payment amount.');
      return;
    }

    setState(() => _verifyingTopUp = true);

    final resolvedPaise = amountInPaise ?? (amountInRupees * 100);
    final result = await WalletService.verifyTopUp(
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: signature,
      amountInRupees: amountInRupees,
      amountInPaise: resolvedPaise,
      token: widget.token,
    );

    if (!mounted) return;

    setState(() => _verifyingTopUp = false);

    if (result.ok) {
      setState(() {
        _pendingOrder = null;
        _pendingOrderAmountInRupees = null;
        _pendingOrderAmountInPaise = null;
      });
      _showSnack('Payment verified successfully.');
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

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final balanceText = _balance != null
        ? '₹${(_balance!.balancePaise / 100).toStringAsFixed(2)}'
        : '₹0.00';
    final refreshing = _loadingBalance || _verifyingTopUp;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        centerTitle: true,
        backgroundColor: _kAppbarOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_verifyingTopUp || _creatingOrder)
            const LinearProgressIndicator(minHeight: 2, color: _kPrimaryYellow),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadBalance(silently: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Balance card (light cream)
                  Container(
                    decoration: BoxDecoration(
                      color: _kBalanceBg,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Balance',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        refreshing
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.2),
                              )
                            : Text(
                                balanceText,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: _kTextPrimary,
                                ),
                              ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Add Money button (yellow pill, bold & larger text, black for contrast)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kPrimaryYellow,
                        foregroundColor: Colors.black87, // improved contrast
                        minimumSize: const Size.fromHeight(54),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900, // bold
                          fontSize: 16, // larger
                          letterSpacing: .2,
                        ),
                      ),
                      onPressed: _creatingOrder ? null : _promptTopUp,
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(_creatingOrder ? 'Creating order…' : 'Add Money'),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Info card (light cream)
                  Container(
                    decoration: BoxDecoration(
                      color: _kInfoBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE9E2B8)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'How it works',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _kTextPrimary,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Add money using Razorpay. After successful payment, the transaction is verified and your balance refreshes automatically.',
                          style: TextStyle(height: 1.4, color: _kTextSecondary),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'For production, update the Razorpay key and prefill details with live credentials.',
                          style: TextStyle(fontSize: 13, color: _kTextSecondary),
                        ),
                      ],
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

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: _kPrimaryYellow.withOpacity(0.18),
        side: const BorderSide(color: _kPrimaryYellow, width: .6),
        label: Text(
          label,
          style: const TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.w700, // bolder chips too
          ),
        ),
        onPressed: onTap,
      ),
    );
  }
}
