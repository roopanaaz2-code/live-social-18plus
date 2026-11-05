import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

class VipScreen extends StatefulWidget {
  const VipScreen({super.key});
  @override
  State<VipScreen> createState() => _VipScreenState();
}

class _VipScreenState extends State<VipScreen> {
  bool? _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await Supabase.instance.client.rpc('has_vip_access');
      if (mounted) setState(() => _active = value == true);
    } catch (_) {
      if (mounted) setState(() { _active = false; _error = 'VIP status could not be checked.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(
      backgroundColor: _dark,
      title: const Text('NIGHTLINK VIP', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
    ),
    body: _active == null
      ? const Center(child: CircularProgressIndicator(color: _gold))
      : ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Icon(Icons.workspace_premium, color: _gold, size: 76),
            const SizedBox(height: 14),
            const Text('VIP MEMBERSHIP', textAlign: TextAlign.center,
              style: TextStyle(color: _gold, fontSize: 25, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              _active! ? 'VIP access is active on this account.' : 'Discover the NightLink VIP benefits.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent)),
            ),
            const SizedBox(height: 22),
            for (final item in const [
              ['No advertising', 'Enjoy NightLink without banner ads.'],
              ['VIP profile badge', 'Show a special VIP status on your profile.'],
              ['Exclusive profile styling', 'Stand out with premium profile presentation.'],
              ['Priority community support', 'Get help with account and app issues.'],
            ])
              Card(
                color: const Color(0xFF11182B),
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: _blue),
                  title: Text(item[0], style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                  subtitle: Text(item[1], style: const TextStyle(color: Colors.white60)),
                ),
              ),
            const SizedBox(height: 18),
            if (_active!)
              const Card(
                color: Color(0xFF17233D),
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('DEVELOPER VIP: lifetime access is enabled for the NightLink developer account. All gifts are free on this account.',
                    textAlign: TextAlign.center, style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                ),
              )
            else
              const Card(
                color: Color(0xFF17233D),
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('VIP checkout is not enabled yet. No payment will be taken until a real payment provider and verified purchase flow are configured.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
                ),
              ),
          ],
        ),
  );
}
