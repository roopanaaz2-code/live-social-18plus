import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _bannerAdUnitId = String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID');
const _useTestAds = bool.fromEnvironment('ADMOB_USE_TEST_ADS', defaultValue: true);
const _googleTestBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

String get _activeBannerAdUnitId =>
    _useTestAds ? _googleTestBannerAdUnitId : _bannerAdUnitId;

final ValueNotifier<bool> nightLinkAdsReady = ValueNotifier<bool>(false);
final ValueNotifier<bool> nightLinkPrivacyOptionsRequired =
    ValueNotifier<bool>(false);
final ValueNotifier<String> nightLinkAdsStatus =
    ValueNotifier<String>('Advertising has not been initialized.');

bool _consentRequestInFlight = false;
bool _mobileAdsInitialized = false;
bool _mobileAdsInitializing = false;
Timer? _consentFallbackTimer;

Future<void> initializeNightLinkAds() {
  if (!_useTestAds && _bannerAdUnitId.isEmpty) {
    nightLinkAdsReady.value = false;
    nightLinkAdsStatus.value =
        'Advertising is disabled: the production banner ad unit ID is missing.';
    debugPrint(nightLinkAdsStatus.value);
    return Future<void>.value();
  }

  if (_consentRequestInFlight) return Future<void>.value();

  _consentRequestInFlight = true;
  nightLinkAdsStatus.value = 'Checking Google advertising consent…';
  debugPrint(
    'NightLink AdMob starting. '
    'Test ads: $_useTestAds. '
    'Banner unit configured: ${_useTestAds || _bannerAdUnitId.isNotEmpty}.',
  );

  _consentFallbackTimer?.cancel();
  _consentFallbackTimer = Timer(const Duration(seconds: 12), () {
    if (!_consentRequestInFlight) return;
    debugPrint(
      'NightLink UMP update timed out; checking whether an existing consent '
      'decision still permits ad requests.',
    );
    _consentRequestInFlight = false;
    _refreshPrivacyOptionsRequirement();
    _initializeAdsIfAllowed();
  });

  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () {
      _consentFallbackTimer?.cancel();
      _consentRequestInFlight = false;
      debugPrint('NightLink UMP consent information updated.');
      _refreshPrivacyOptionsRequirement();
      ConsentForm.loadAndShowConsentFormIfRequired((formError) {
        if (formError != null) {
          debugPrint(
            'NightLink UMP consent form: '
            '${formError.errorCode} ${formError.message}',
          );
        } else {
          debugPrint('NightLink UMP consent form flow completed.');
        }
        _initializeAdsIfAllowed();
      });
    },
    (formError) {
      _consentFallbackTimer?.cancel();
      _consentRequestInFlight = false;
      debugPrint(
        'NightLink UMP consent update failed: '
        '${formError.errorCode} ${formError.message}',
      );
      _refreshPrivacyOptionsRequirement();
      _initializeAdsIfAllowed();
    },
  );

  return Future<void>.value();
}

Future<void> _refreshPrivacyOptionsRequirement() async {
  try {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    final required = status == PrivacyOptionsRequirementStatus.required;
    nightLinkPrivacyOptionsRequired.value = required;
    debugPrint('NightLink UMP privacy options required: $required ($status).');
  } catch (error) {
    nightLinkPrivacyOptionsRequired.value = false;
    debugPrint('NightLink UMP privacy requirement check failed: $error');
  }
}

Future<void> _initializeAdsIfAllowed() async {
  try {
    final canRequestAds =
        await ConsentInformation.instance.canRequestAds();
    debugPrint('NightLink UMP canRequestAds: $canRequestAds');

    if (!canRequestAds) {
      nightLinkAdsReady.value = false;
      nightLinkAdsStatus.value =
          'Google has not confirmed that ads can be requested yet.';
      return;
    }

    if (_mobileAdsInitialized) {
      nightLinkAdsReady.value = true;
      nightLinkAdsStatus.value = _useTestAds
          ? 'Google test ads are ready. Test ads do not generate earnings.'
          : 'Google Mobile Ads is ready.';
      return;
    }

    if (_mobileAdsInitializing) return;
    _mobileAdsInitializing = true;

    try {
      await MobileAds.instance.initialize();
      _mobileAdsInitialized = true;
      nightLinkAdsReady.value = true;
      nightLinkAdsStatus.value = _useTestAds
          ? 'Google test ads are ready. Test ads do not generate earnings.'
          : 'Google Mobile Ads is ready.';
      debugPrint(nightLinkAdsStatus.value);
    } finally {
      _mobileAdsInitializing = false;
    }
  } catch (error) {
    nightLinkAdsReady.value = false;
    nightLinkAdsStatus.value = 'Google Ads initialization failed: $error';
    debugPrint(nightLinkAdsStatus.value);
  }
}

class NightLinkPrivacyOptionsButton extends StatelessWidget {
  const NightLinkPrivacyOptionsButton({super.key});

  Future<void> _showPrivacyOptions(BuildContext context) async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      final required = status == PrivacyOptionsRequirementStatus.required;
      nightLinkPrivacyOptionsRequired.value = required;

      if (!required) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google does not currently require a privacy options form.'),
            ),
          );
        }
        return;
      }

      ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          debugPrint(
            'NightLink privacy options failed: '
            '${formError.errorCode} ${formError.message}',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Privacy options unavailable: ${formError.message}'),
              ),
            );
          }
        }
        _refreshPrivacyOptionsRequirement();
        _initializeAdsIfAllowed();
      });
    } catch (error) {
      debugPrint('NightLink privacy options check failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google privacy options are not available yet.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => _showPrivacyOptions(context),
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
  int _retryCount = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    nightLinkAdsReady.addListener(_handleAdsReadyChanged);
    _load();
  }

  void _handleAdsReadyChanged() {
    if (!mounted) return;
    if (nightLinkAdsReady.value) {
      _load();
    } else {
      _retryTimer?.cancel();
      _banner?.dispose();
      _banner = null;
      _loaded = false;
      setState(() {});
    }
  }

  void _load() {
    if (widget.hide ||
        !nightLinkAdsReady.value ||
        _banner != null ||
        (!_useTestAds && _bannerAdUnitId.isEmpty)) {
      return;
    }

    final ad = BannerAd(
      adUnitId: _activeBannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          _retryCount = 0;
          setState(() => _loaded = true);
          debugPrint('NightLink banner ad loaded successfully.');
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (identical(_banner, ad)) _banner = null;
          _loaded = false;
          debugPrint('NightLink banner failed to load: $error');

          if (mounted && _retryCount < 2 && !widget.hide) {
            _retryCount++;
            _retryTimer?.cancel();
            _retryTimer = Timer(
              Duration(seconds: 4 * _retryCount),
              _load,
            );
          }
          if (mounted) setState(() {});
        },
      ),
    );

    _banner = ad;
    ad.load();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant NightLinkBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hide && !oldWidget.hide) {
      _retryTimer?.cancel();
      _banner?.dispose();
      _banner = null;
      _loaded = false;
    } else if (!widget.hide && oldWidget.hide) {
      _load();
    }
  }

  @override
  void dispose() {
    nightLinkAdsReady.removeListener(_handleAdsReadyChanged);
    _retryTimer?.cancel();
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hide || !nightLinkAdsReady.value) {
      return const SizedBox.shrink();
    }
    final ad = _banner;
    if (ad == null || !_loaded) {
      return const SizedBox(height: 50);
    }
    return Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
