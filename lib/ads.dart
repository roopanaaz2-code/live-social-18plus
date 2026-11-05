import 'package:flutter/material.dart';

// AdMob is intentionally disabled until NightLink has a real, verified
// AdMob application ID and banner unit ID. The stub keeps the home screen
// layout stable without loading an SDK ContentProvider at app startup.
Future<void> initializeNightLinkAds() async {}

class NightLinkBannerAd extends StatelessWidget {
  const NightLinkBannerAd({super.key, required this.hide});

  final bool hide;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
