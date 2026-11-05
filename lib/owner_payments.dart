import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _ownerEmail = 'roopanaaz2@gmail.com';
const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

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
    final email = _client.auth.currentUser?.email?.toLowerCase();
    if (email != _ownerEmail) {
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
    final email = _client.auth.currentUser?.email?.toLowerCase();
    if (email != _ownerEmail) {
      return const Scaffold(
        backgroundColor: _dark,
        body: Center(child: Text('Access denied', style: TextStyle(color: Colors.redAccent))),
      );
    }

    final paid = _orders.where((o) => o['status']?.toString().toLowerCase() == 'paid').toList();
    final total = paid.fold<double>(0, (sum, o) => sum + ((o['amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        title: const Text('OWNER PAYMENTS', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, color: _blue))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFF17233D),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('VERIFIED PAYMENTS', style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 8),
                          Text('${total.toStringAsFixed(2)} total', style: const TextStyle(color: _gold, fontSize: 28, fontWeight: FontWeight.bold)),
                          Text('${paid.length} paid orders • latest 100 orders shown below', style: const TextStyle(color: Colors.white60)),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                  const SizedBox(height: 12),
                  const Text('PAYMENT ACTIVITY', style: TextStyle(color: _gold, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  if (_orders.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No payment records yet. Payments will appear here after a payment provider is connected and verifies them.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                    ),
                  ..._orders.map((order) {
                    final amount = (order['amount'] as num?)?.toDouble() ?? 0;
                    final status = order['status']?.toString() ?? 'unknown';
                    final created = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
                    return Card(
                      color: const Color(0xFF11182B),
                      child: ListTile(
                        title: Text('${order['coins']} coins • ${amount.toStringAsFixed(2)} ${order['currency']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('User: ${order['user_id']}\n${created?.toString() ?? 'Date unavailable'}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                        isThreeLine: true,
                        trailing: Text(status.toUpperCase(), style: TextStyle(color: status.toLowerCase() == 'paid' ? Colors.greenAccent : _gold, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
