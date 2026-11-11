import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _admobAppId = String.fromEnvironment('ADMOB_ANDROID_APP_ID');
const _bannerAdUnitId = String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID');

bool nightLinkAdsReady = false;

Future<void> initializeNightLinkAds() async {
  nightLinkAdsReady = false;
  if (_admobAppId.isEmpty || _bannerAdUnitId.isEmpty) {
    debugPrint('NightLink AdMob is disabled: add the AdMob app ID and banner unit ID secrets.');
    return;
  }

  final completed = Completer<void>();

  Future<void> finishConsent() async {
    try {
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (canRequest) {
        await MobileAds.instance.initialize();
        nightLinkAdsReady = true;
      }
    } catch (error) {
      debugPrint('NightLink AdMob consent/init failed: $error');
    } finally {
      if (!completed.isCompleted) completed.complete();
    }
  }

  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () {
      ConsentForm.loadAndShowConsentFormIfRequired((_) {
        finishConsent();
      });
    },
    (_) {
      finishConsent();
    },
  );

  try {
    await completed.future.timeout(const Duration(seconds: 12));
  } on TimeoutException {
    debugPrint('NightLink AdMob consent request timed out; ads remain disabled for this launch.');
  }
}

class NightLinkPrivacyOptionsButton extends StatelessWidget {
  const NightLinkPrivacyOptionsButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () {
          ConsentForm.showPrivacyOptionsForm((error) {
            if (error != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Privacy options unavailable: ${error.message}')),
              );
            }
          });
        },
        icon: const Icon(Icons.privacy_tip_outlined),
        label: const Text('Advertising privacy options'),
      );
}

class NightLinkBannerAd extends StatefulWidget {
  const NightLinkBannerAd({super.key, required this.hide});

  final bool hide;

  @override
  State<NightLinkBannerAd> createState() => _NightLinkBannerAdState();
}

class _NightLinkBannerAdState extends State<NightLinkBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (widget.hide || !nightLinkAdsReady || _banner != null) return;
    final ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      request: AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (identical(_banner, ad)) _banner = null;
          debugPrint('NightLink banner failed to load: $error');
        },
      ),
    );
    _banner = ad;
    ad.load();
  }

  @override
  void didUpdateWidget(covariant NightLinkBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hide && !oldWidget.hide) {
      _banner?.dispose();
      _banner = null;
      _loaded = false;
    } else if (!widget.hide && oldWidget.hide) {
      _load();
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hide || !nightLinkAdsReady) return const SizedBox.shrink();
    final ad = _banner;
    if (ad == null || !_loaded) return const SizedBox(height: 50);
    return Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
