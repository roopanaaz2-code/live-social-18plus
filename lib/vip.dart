import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nightlink_design.dart';

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
        backgroundColor: NightLinkDesign.background,
        appBar: AppBar(
          backgroundColor: NightLinkDesign.background,
          title: const Text('NightLink VIP'),
        ),
        body: _active == null
            ? const Center(child: CircularProgressIndicator(color: NightLinkDesign.gold))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                children: [
                  NightLinkPanel(
                    accent: NightLinkDesign.gold,
                    gradient: true,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    child: Column(
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: NightLinkDesign.gold.withOpacity(.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.workspace_premium_rounded, color: NightLinkDesign.gold, size: 36),
                        ),
                        const SizedBox(height: 17),
                        NightLinkDesign.eyebrow('NightLink membership', color: NightLinkDesign.gold),
                        const SizedBox(height: 7),
                        Text(
                          _active! ? 'VIP access is active' : 'NightLink VIP',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: NightLinkDesign.text, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.4),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _active!
                              ? 'VIP access is active on this account.'
                              : 'Explore the benefit currently associated with VIP access.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 14, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    NightLinkPanel(
                      accent: NightLinkDesign.gold,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: NightLinkDesign.gold, size: 19),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 23),
                  NightLinkDesign.eyebrow('Membership benefit', color: NightLinkDesign.blue),
                  const SizedBox(height: 12),
                  NightLinkPanel(
                    accent: NightLinkDesign.blue,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: NightLinkDesign.blue.withOpacity(.13), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.notifications_off_outlined, color: NightLinkDesign.blue),
                        ),
                        const SizedBox(width: 13),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ad-free access', style: TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w700, fontSize: 15)),
                              SizedBox(height: 5),
                              Text('VIP accounts do not receive NightLink banner ads.', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 13, height: 1.4)),
                            ],
                          ),
                        ),
                        if (_active!) const Icon(Icons.check_circle_rounded, color: NightLinkDesign.success, size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  NightLinkPanel(
                    accent: _active! ? NightLinkDesign.gold : NightLinkDesign.blue,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _active! ? Icons.verified_outlined : Icons.lock_outline_rounded,
                          color: _active! ? NightLinkDesign.gold : NightLinkDesign.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _active!
                                ? 'Your account currently has VIP access. This screen reflects account status; it does not manage or renew a subscription.'
                                : 'VIP checkout is not enabled yet. No payment will be taken until a real payment provider and verified purchase flow are configured.',
                            style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      );
}
