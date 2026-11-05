import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const admobAndroidAppId = String.fromEnvironment('ADMOB_ANDROID_APP_ID');
const admobBannerAdUnitId = String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID');

Future<void> initializeNightLinkAds() async {
  if (admobAndroidAppId.isNotEmpty && admobBannerAdUnitId.isNotEmpty) {
    await MobileAds.instance.initialize();
  }
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

  @override
  void didUpdateWidget(covariant NightLinkBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hide != widget.hide) {
      if (widget.hide) {
        _banner?.dispose();
        _banner = null;
        _loaded = false;
      } else {
        _load();
      }
    }
  }

  void _load() {
    if (widget.hide || admobBannerAdUnitId.isEmpty || admobAndroidAppId.isEmpty || _banner != null) return;
    final ad = BannerAd(
      adUnitId: admobBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || widget.hide) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() { _banner = null; _loaded = false; });
          debugPrint('NightLink AdMob banner failed: ${error.code}');
        },
      ),
    );
    _banner = ad;
    ad.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hide || admobBannerAdUnitId.isEmpty || admobAndroidAppId.isEmpty) {
      return const SizedBox.shrink();
    }
    final ad = _banner;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
