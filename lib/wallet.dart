import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nightlink_design.dart';
import 'owner_payments.dart';

class CoinWalletScreen extends StatefulWidget {
  const CoinWalletScreen({super.key});

  @override
  State<CoinWalletScreen> createState() => _CoinWalletScreenState();
}

class _CoinWalletScreenState extends State<CoinWalletScreen>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;
  int _balance = 0;
  int _giftCoinsReceived = 0;
  int _giftsReceived = 0;
  List<Map<String, dynamic>> _packages = [];
  bool get _isDeveloper =>
      _client.auth.currentUser?.id == 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd';
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
        _client.from('battle_gifts').select('coins_spent, quantity')
            .eq('recipient_id', user.id),
      ]);
      if (!mounted) return;
      final wallet = results[0] as Map<String, dynamic>?;
      final received = (results[2] as List).cast<Map<String, dynamic>>();
      final giftCoins = received.fold<int>(0, (sum, gift) =>
          sum + ((gift['coins_spent'] as num?)?.toInt() ?? 0));
      final giftCount = received.fold<int>(0, (sum, gift) =>
          sum + ((gift['quantity'] as num?)?.toInt() ?? 1));
      setState(() {
        _balance = (wallet?['balance'] as num?)?.toInt() ?? 0;
        _packages = (results[1] as List).cast<Map<String, dynamic>>();
        _giftCoinsReceived = giftCoins;
        _giftsReceived = giftCount;
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
      backgroundColor: NightLinkDesign.background,
      appBar: AppBar(
        backgroundColor: NightLinkDesign.background,
        title: const Text('Coin wallet'),
        actions: [
          IconButton(
            tooltip: 'Refresh wallet',
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
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                children: [
                  NightLinkPanel(
                    accent: NightLinkDesign.gold,
                    gradient: true,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: NightLinkDesign.gold.withOpacity(.13),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(Icons.monetization_on_rounded,
                                  color: NightLinkDesign.gold, size: 27),
                            ),
                            const SizedBox(width: 13),
                            Expanded(child: NightLinkDesign.eyebrow('Your balance', color: NightLinkDesign.gold)),
                            if (_isDeveloper)
                              _StatusPill(label: 'DEVELOPER VIP', color: NightLinkDesign.gold),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isDeveloper ? 'UNLIMITED' : '$_balance',
                          style: const TextStyle(
                            color: NightLinkDesign.text,
                            fontSize: 38,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _isDeveloper ? 'Developer account balance' : 'NightLink coins available',
                          style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  NightLinkPanel(
                    accent: NightLinkDesign.blue,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.card_giftcard_rounded, color: NightLinkDesign.blue),
                            const SizedBox(width: 10),
                            Expanded(child: NightLinkDesign.eyebrow('Gift transparency')),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(child: _GiftMetric(value: '$_giftsReceived', label: 'Gifts received')),
                            Container(width: 1, height: 45, color: Colors.white.withOpacity(.09)),
                            Expanded(child: _GiftMetric(value: '$_giftCoinsReceived', label: 'Sender coins spent')),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NightLinkDesign.background.withOpacity(.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: NightLinkDesign.textMuted, size: 18),
                              SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Gift value is shown for transparency. It is not a cash payout or withdrawable balance until a verified creator-payout system is added.',
                                  style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12, height: 1.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _MessagePanel(message: _error!, color: NightLinkDesign.error, icon: Icons.error_outline_rounded),
                  ],
                  const SizedBox(height: 26),
                  if (_isDeveloper)
                    NightLinkPanel(
                      accent: NightLinkDesign.gold,
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_user_outlined, color: NightLinkDesign.gold),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Developer VIP is active. All battle gifts are free for this account; no coin purchase is needed.',
                              style: TextStyle(color: NightLinkDesign.text, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    NightLinkDesign.eyebrow('Coin packages', color: NightLinkDesign.gold),
                    const SizedBox(height: 6),
                    const Text(
                      'Available package information',
                      style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 13),
                    if (_packages.isEmpty)
                      const NightLinkPanel(
                        child: Text(
                          'No active coin packages to show right now.',
                          style: TextStyle(color: NightLinkDesign.textMuted),
                        ),
                      )
                    else
                      ..._packages.map(_packageCard),
                    const SizedBox(height: 12),
                    _MessagePanel(
                      message: 'Coin purchases are paused until a verified payment provider is connected. These package cards are informational only; no checkout or payment is available.',
                      color: NightLinkDesign.gold,
                      icon: Icons.lock_outline_rounded,
                    ),
                  ],
                  if (_client.auth.currentUser?.id == 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd') ...[
                    const SizedBox(height: 22),
                    NightLinkPanel(
                      accent: NightLinkDesign.blue,
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
                        leading: const Icon(Icons.admin_panel_settings_outlined, color: NightLinkDesign.gold),
                        title: const Text('Owner payment dashboard', style: TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w700)),
                        subtitle: const Text('Private payment records · owner account only', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: NightLinkDesign.blue, size: 17),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NightLinkPanel(
        accent: NightLinkDesign.blue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: NightLinkDesign.gold.withOpacity(.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.toll_rounded, color: NightLinkDesign.gold),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$coins coins', style: const TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('${amount.toStringAsFixed(2)} $currency', style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: NightLinkDesign.gold.withOpacity(.1), borderRadius: BorderRadius.circular(99)),
              child: const Text('COMING SOON', style: TextStyle(color: NightLinkDesign.gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .55)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftMetric extends StatelessWidget {
  const _GiftMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: NightLinkDesign.text, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 11, height: 1.3)),
          ],
        ),
      );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message, required this.color, required this.icon});

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => NightLinkPanel(
        accent: color,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12, height: 1.45))),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .4)),
      );
}
