import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ads.dart';
import 'profile.dart';
import 'connections.dart';
import 'vip.dart';
import 'matchmaking.dart';
import 'chat.dart';
import 'live_call.dart';
import 'wallet.dart';
import 'feed.dart';
import 'ai_assistant.dart';
import 'nightlink_design.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://falimxmpicqaakjnigkv.supabase.co',
);
const supabaseKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

const gold = NightLinkDesign.gold;
const blue = NightLinkDesign.blue;
const dark = NightLinkDesign.background;
const supportEmail = 'roopanaaz2@gmail.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseKey.isEmpty) {
    runApp(const SetupErrorApp(
      message: 'Supabase key is missing. Check GitHub Actions variables.',
    ));
    return;
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
    );
  } catch (error, stackTrace) {
    debugPrint('NightLink Supabase startup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(SetupErrorApp(
      message: 'NightLink could not initialize its backend.\n\n$error',
    ));
    return;
  }

  // Ads are optional and must never prevent the core app from opening.
  try {
    await initializeNightLinkAds();
  } catch (error, stackTrace) {
    debugPrint('NightLink optional ads initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const NightLinkApp());
}

class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: NightLinkDesign.theme(),
      home: Scaffold(
        backgroundColor: dark,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: NightLinkPanel(
              accent: gold,
              child: SelectableText(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: gold, height: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NightLinkApp extends StatelessWidget {
  const NightLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: nightLinkNavigatorKey,
      title: 'NightLink Live',
      theme: NightLinkDesign.theme(),
      builder: (context, child) => IncomingCallOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AgeScreen(),
    );
  }
}

class AgeScreen extends StatefulWidget {
  const AgeScreen({super.key});

  @override
  State<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends State<AgeScreen> {
  bool accepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF111B2D), dark, dark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: NightLinkPanel(
                  accent: gold,
                  gradient: true,
                  padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: gold.withOpacity(.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: gold.withOpacity(.22)),
                        ),
                        child: const Icon(Icons.nightlight_round, color: gold, size: 42),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'NIGHTLINK',
                        style: TextStyle(
                          color: gold,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      NightLinkDesign.eyebrow('Connect  •  Chat  •  Compete'),
                      const SizedBox(height: 30),
                      const Text(
                        'WELCOME TO THE 18+ COMMUNITY',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Meet people, enjoy conversations, send messages '
                        'and compete in exciting battles.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: NightLinkDesign.textMuted, height: 1.6),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        decoration: BoxDecoration(
                          color: dark.withOpacity(.42),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: CheckboxListTile(
                          value: accepted,
                          activeColor: gold,
                          onChanged: (value) {
                            setState(() => accepted = value ?? false);
                          },
                          title: const Text(
                            'I confirm that I am 18 years old or older.',
                            style: TextStyle(fontSize: 13, height: 1.35),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: accepted
                              ? () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const AuthGate(),
                                    ),
                                  );
                                }
                              : null,
                          child: const Text('ENTER NIGHTLINK'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '18+ AGE GATE  •  RESPECT  •  PRIVACY',
                        style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = client.auth.currentSession;

        if (session != null) {
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  bool isSignup = false;
  bool loading = false;
  bool obscurePassword = true;
  String message = '';

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final name = nameController.text.trim();

    if (email.isEmpty || password.isEmpty ||
        (isSignup && name.isEmpty)) {
      setState(() => message = 'Please complete all fields.');
      return;
    }

    if (password.length < 6) {
      setState(() => message = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      final auth = Supabase.instance.client.auth;

      if (isSignup) {
        final result = await auth.signUp(
          email: email,
          password: password,
          data: {'display_name': name},
        );

        if (!mounted) return;

        if (result.session == null) {
          setState(() {
            message = 'Account created! Check your email and verify '
                'your account before logging in.';
          });
        }
      } else {
        await auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (error) {
      if (mounted) setState(() => message = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: NightLinkPanel(
                accent: blue,
                padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: gold.withOpacity(.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.nightlight_round, color: gold, size: 36),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'NIGHTLINK',
                      style: TextStyle(
                        color: gold,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    NightLinkDesign.eyebrow(
                      isSignup ? 'Create your account' : 'Welcome back',
                    ),
                    const SizedBox(height: 28),
                    if (isSignup) ...[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: obscurePassword ? 'Show password' : 'Hide password',
                          icon: Icon(
                            obscurePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() => obscurePassword = !obscurePassword);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 15),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: gold, height: 1.4),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: loading ? null : submit,
                        child: loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isSignup ? 'CREATE ACCOUNT' : 'LOGIN'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              setState(() {
                                isSignup = !isSignup;
                                message = '';
                              });
                            },
                      child: Text(
                        isSignup
                            ? 'Already have an account? Login'
                            : 'New to NightLink? Create account',
                        style: const TextStyle(color: blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _vipLoading = true;
  bool _hasVip = false;
  String? _profileName;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadVip();
  }

  Future<void> _loadVip() async {
    try {
      final client = Supabase.instance.client;
      final vipValue = await client.rpc('has_vip_access');
      final profile = await client.from('profiles').select('display_name')
          .eq('id', client.auth.currentUser!.id).maybeSingle();
      if (mounted) setState(() {
        _hasVip = vipValue == true;
        _profileName = profile?['display_name']?.toString();
        _vipLoading = false;
      });
    } catch (_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (mounted) setState(() {
        _hasVip = userId == 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd';
        _vipLoading = false;
      });
    }
  }

  Future<void> _contactUs() async {
    if (supportEmail.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support email is not configured yet.')),
      );
      return;
    }
    // Prefer the Gmail app when installed, then fall back to the Android
    // default mail handler so Contact Us still works without Gmail.
    final gmailUri = Uri(
      scheme: 'googlegmail',
      host: 'co',
      queryParameters: {
        'to': supportEmail,
        'subject': 'NightLink Support',
      },
    );
    final mailtoUri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {'subject': 'NightLink Support'},
    );
    var opened = false;
    try {
      if (await canLaunchUrl(gmailUri)) {
        opened = await launchUrl(gmailUri, mode: LaunchMode.externalApplication);
      }
      if (!opened) {
        opened = await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      debugPrint('NightLink Contact Us launch failed: $error');
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app is available on this device.')),
      );
    }
  }

  Widget _homeContent(String name, bool hideAds) {
    final actions = <Widget>[
      _HomeActionCard(
        icon: Icons.person_search,
        title: 'FIND PEOPLE & CONNECTIONS',
        subtitle: 'Edit your username, search members and accept requests',
        color: gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen())),
      ),
      _HomeActionCard(
        icon: Icons.play_circle_outline,
        title: 'SHORT VIDEO FEED',
        subtitle: 'Watch, upload and share short videos',
        color: gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NightLinkFeedScreen())),
      ),
      _HomeActionCard(
        icon: Icons.auto_awesome,
        title: 'NIGHTLINK AI',
        subtitle: 'Ask questions, get smart help and talk by microphone',
        color: blue,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NightLinkAiScreen())),
      ),
      _HomeActionCard(
        icon: Icons.chat_bubble_outline,
        title: 'TEXT CHAT',
        subtitle: 'Chat privately with accepted connections',
        color: gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
      ),
      _HomeActionCard(
        icon: Icons.mic_none,
        title: 'VOICE CHAT',
        subtitle: 'Talk live with accepted connections',
        color: blue,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.voice))),
      ),
      _HomeActionCard(
        icon: Icons.videocam_outlined,
        title: 'VIDEO CHAT',
        subtitle: 'Meet face-to-face with accepted connections',
        color: gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.video))),
      ),
      _HomeActionCard(
        icon: Icons.monetization_on_outlined,
        title: 'COINS & GIFTS',
        subtitle: 'View your coin wallet and gifts',
        color: gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoinWalletScreen())),
      ),
      _HomeActionCard(
        icon: Icons.workspace_premium,
        title: 'VIP MEMBERSHIP',
        subtitle: _hasVip ? 'VIP is active on this account' : 'Explore VIP benefits',
        color: gold,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VipScreen())),
      ),
      _HomeActionCard(
        icon: Icons.sports_esports,
        title: 'FIND A MATCH',
        subtitle: '1v1 duels and team battles',
        color: blue,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MatchLobby())),
      ),
      _HomeActionCard(
        icon: Icons.support_agent,
        title: 'CONTACT US',
        subtitle: 'Send a private message to NightLink support',
        color: blue,
        onTap: _contactUs,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 1080
            ? 1040.0
            : constraints.maxWidth - 40;
        final columns = contentWidth >= 720 ? 2 : 1;
        final cardWidth = columns == 2 ? (contentWidth - 14) / 2 : contentWidth;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NightLinkPanel(
                      accent: gold,
                      gradient: true,
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: gold.withOpacity(.13),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.nightlight_round, color: gold, size: 31),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                NightLinkDesign.eyebrow('Your NightLink'),
                                const SizedBox(height: 6),
                                Text(
                                  'Welcome, $name',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Find your people. Start a conversation.',
                                  style: TextStyle(color: NightLinkDesign.textMuted, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Choose how you want to connect',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Everything you need, all in one place.',
                      style: TextStyle(color: NightLinkDesign.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: actions
                          .map((action) => SizedBox(width: cardWidth, child: action))
                          .toList(),
                    ),
                    if (!_vipLoading) ...[
                      const SizedBox(height: 22),
                      NightLinkBannerAd(hide: hideAds),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _selectedContent(String name, bool hideAds) {
    if (_selectedTab == 0) return _homeContent(name, hideAds);
    if (_selectedTab == 1) return const MatchLobby();
    if (_selectedTab == 2) return const NightLinkFeedScreen();
    if (_selectedTab == 3) return const ChatScreen();
    return const ProfileScreen();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = _profileName ?? user?.userMetadata?['display_name'] ?? 'Member';
    final hideAds = _hasVip || user?.id == 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd';

    return Scaffold(
      appBar: _selectedTab == 0 ? AppBar(
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: gold, size: 21),
            SizedBox(width: 10),
            Text('NIGHTLINK', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: blue),
            onPressed: () async => Supabase.instance.client.auth.signOut(),
          ),
          const SizedBox(width: 6),
        ],
      ) : null,
      body: _selectedContent(name, hideAds),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        backgroundColor: NightLinkDesign.backgroundRaised,
        indicatorColor: gold.withOpacity(.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle_fill),
            label: 'Short Videos',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: NightLinkDesign.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 112,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withOpacity(.13),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NightLinkDesign.textMuted,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 19, color: color.withOpacity(.78)),
                ],
              ),
            ),
          ),
        ),
      );
}
