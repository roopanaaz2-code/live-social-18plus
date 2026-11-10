import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nightlink_design.dart';

const _ownerUserId = 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd';

class OwnerPaymentsScreen extends StatefulWidget {
  const OwnerPaymentsScreen({super.key});

  @override
  State<OwnerPaymentsScreen> createState() => _OwnerPaymentsScreenState();
}

class _OwnerPaymentsScreenState extends State<OwnerPaymentsScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId != _ownerUserId) {
      setState(() {
        _loading = false;
        _error = 'This dashboard is restricted to the owner account.';
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _client
          .from('coin_orders')
          .select('id, user_id, package_code, coins, amount, currency, status, created_at, paid_at')
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _orders = rows.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load payment records. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _client.auth.currentUser?.id;
    if (userId != _ownerUserId) {
      return const Scaffold(
        backgroundColor: NightLinkDesign.background,
        body: Center(child: Text('Access denied', style: TextStyle(color: NightLinkDesign.error))),
      );
    }

    final paid = _orders.where((o) => o['status']?.toString().toLowerCase() == 'paid').toList();
    final total = paid.fold<double>(0, (sum, o) => sum + ((o['amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: NightLinkDesign.background,
      appBar: AppBar(
        backgroundColor: NightLinkDesign.background,
        title: const Text('Owner payments'),
        actions: [
          IconButton(
            tooltip: 'Refresh payment records',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: NightLinkDesign.blue),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NightLinkDesign.gold))
          : RefreshIndicator(
              onRefresh: _load,
              color: NightLinkDesign.gold,
              backgroundColor: NightLinkDesign.surface,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                children: [
                  NightLinkPanel(
                    accent: NightLinkDesign.gold,
                    gradient: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(color: NightLinkDesign.gold.withOpacity(.12), borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.account_balance_wallet_outlined, color: NightLinkDesign.gold),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: NightLinkDesign.eyebrow('Paid amount sum · loaded records', color: NightLinkDesign.gold)),
                          ],
                        ),
                        const SizedBox(height: 19),
                        Text(
                          '${total.toStringAsFixed(2)} ${_summaryCurrency(paid)}',
                          style: const TextStyle(color: NightLinkDesign.text, fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -.5),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${paid.length} paid ${paid.length == 1 ? 'order' : 'orders'} in the latest ${_orders.length} records. No currency conversion is applied.',
                          style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    NightLinkPanel(
                      accent: NightLinkDesign.error,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: NightLinkDesign.error, size: 19),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(child: NightLinkDesign.eyebrow('Payment activity', color: NightLinkDesign.gold)),
                      _CountPill(count: _orders.length),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_orders.isEmpty && _error == null)
                    NightLinkPanel(
                      accent: NightLinkDesign.blue,
                      child: const Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, color: NightLinkDesign.blue, size: 30),
                          SizedBox(height: 11),
                          Text(
                            'No payment records yet',
                            style: TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Payments will appear here after a payment provider is connected and verifies them.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ..._orders.map(_paymentCard),
                ],
              ),
            ),
    );
  }

  String _summaryCurrency(List<Map<String, dynamic>> paid) {
    final currencies = paid
        .map((order) => order['currency']?.toString().toUpperCase())
        .whereType<String>()
        .where((currency) => currency.isNotEmpty)
        .toSet();
    if (currencies.length == 1) return currencies.first;
    if (currencies.isEmpty) return '';
    return 'mixed currencies';
  }

  Widget _paymentCard(Map<String, dynamic> order) {
    final amount = (order['amount'] as num?)?.toDouble() ?? 0;
    final currency = order['currency']?.toString() ?? '';
    final status = order['status']?.toString() ?? 'unknown';
    final isPaid = status.toLowerCase() == 'paid';
    final created = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NightLinkPanel(
        accent: isPaid ? NightLinkDesign.success : NightLinkDesign.blue,
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${order['coins']} coins',
                    style: const TextStyle(color: NightLinkDesign.text, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                _PaymentStatusPill(label: status.toUpperCase(), paid: isPaid),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${amount.toStringAsFixed(2)} $currency',
              style: const TextStyle(color: NightLinkDesign.gold, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 13),
            const Divider(height: 1),
            const SizedBox(height: 11),
            _DetailLine(label: 'User', value: order['user_id']?.toString() ?? 'Unavailable'),
            const SizedBox(height: 6),
            _DetailLine(label: 'Created', value: created?.toString() ?? 'Date unavailable'),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 57, child: Text(label, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 11))),
          Expanded(child: Text(value, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 11, height: 1.35))),
        ],
      );
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: NightLinkDesign.blue.withOpacity(.12), borderRadius: BorderRadius.circular(99)),
        child: Text('$count records', style: const TextStyle(color: NightLinkDesign.blue, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

class _PaymentStatusPill extends StatelessWidget {
  const _PaymentStatusPill({required this.label, required this.paid});

  final String label;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final color = paid ? NightLinkDesign.success : NightLinkDesign.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .45)),
    );
  }
}
