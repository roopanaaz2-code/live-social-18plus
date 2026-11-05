import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'owner_payments.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

class CoinWalletScreen extends StatefulWidget {
  const CoinWalletScreen({super.key});

  @override
  State<CoinWalletScreen> createState() => _CoinWalletScreenState();
}

class _CoinWalletScreenState extends State<CoinWalletScreen>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;
  int _balance = 0;
  List<Map<String, dynamic>> _packages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _client.from('coin_wallets').select('balance')
            .eq('user_id', user.id).maybeSingle(),
        _client.from('coin_packages').select('package_code, coins, amount, currency')
            .eq('active', true).order('amount'),
      ]);
      if (!mounted) return;
      final wallet = results[0] as Map<String, dynamic>?;
      setState(() {
        _balance = (wallet?['balance'] as num?)?.toInt() ?? 0;
        _packages = (results[1] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load your wallet. Please try again.'; });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        title: const Text('COINS WALLET', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, color: _blue)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              onRefresh: _load,
              color: _gold,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(colors: [Color(0xFF18335A), Color(0xFF11182B)]),
                      border: Border.all(color: _gold.withOpacity(.45)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.monetization_on, color: _gold, size: 42),
                        const SizedBox(height: 8),
                        const Text('YOUR COIN BALANCE', style: TextStyle(color: Colors.white70, letterSpacing: 1.4)),
                        const SizedBox(height: 5),
                        Text('$_balance', style: const TextStyle(color: _gold, fontSize: 38, fontWeight: FontWeight.bold)),
                        const Text('NIGHTLINK COINS', style: TextStyle(color: _blue, fontSize: 11, letterSpacing: 2)),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text('BUY COINS', style: TextStyle(color: _gold, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  ..._packages.map(_packageCard),
                  const SizedBox(height: 8),
                  const Text(
                    'Coin purchases are temporarily paused. You can choose from the full gift catalog inside a live battle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.5),
                  ),
                  if (_client.auth.currentUser?.email?.toLowerCase() == 'roopanaaz2@gmail.com') ...[
                    const SizedBox(height: 22),
                    Card(
                      color: const Color(0xFF17233D),
                      child: ListTile(
                        leading: const Icon(Icons.admin_panel_settings, color: _gold),
                        title: const Text('OWNER PAYMENT DASHBOARD', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Private payment records visible only to the owner account', style: TextStyle(color: Colors.white60)),
                        trailing: const Icon(Icons.chevron_right, color: _blue),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerPaymentsScreen())),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _packageCard(Map<String, dynamic> pack) {
    final amount = (pack['amount'] as num).toDouble();
    final coins = (pack['coins'] as num).toInt();
    final currency = pack['currency'].toString().toUpperCase();
    return Card(
      color: const Color(0xFF11182B),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0x223FC3FF), child: Icon(Icons.monetization_on, color: _gold)),
        title: Text('$coins Coins', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text('${amount.toStringAsFixed(2)} $currency', style: const TextStyle(color: Colors.white60)),
        trailing: const Text('SOON', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
      ),
    );
  }

}
