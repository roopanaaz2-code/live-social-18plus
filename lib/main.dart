
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ads.dart';
import 'connections.dart';
import 'vip.dart';

import 'matchmaking.dart';
import 'chat.dart';
import 'live_call.dart';
import 'wallet.dart';
import 'feed.dart';
import 'ai_assistant.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://falimxmpicqaakjnigkv.supabase.co',
);
const supabaseKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

const gold = Color(0xFFFFC857);
const blue = Color(0xFF2589FF);
const dark = Color(0xFF090D18);
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
      message: 'NightLink could not initialize its backend.\\n\\n$error',
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
      home: Scaffold(
        backgroundColor: dark,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: gold, height: 1.5),
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: dark,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: blue,
        ),
      ),
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
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF101B35), dark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.nightlight_round, color: gold, size: 75),
            const SizedBox(height: 20),
            const Text(
              'NIGHTLINK',
              style: TextStyle(
                color: gold,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const Text(
              'CONNECT • CHAT • COMPETE',
              style: TextStyle(color: blue, letterSpacing: 2),
            ),
            const SizedBox(height: 40),
            const Text(
              'WELCOME TO THE 18+ COMMUNITY',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            const Text(
              'Meet people, enjoy conversations, send messages '
              'and compete in exciting battles.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.6),
            ),
            const SizedBox(height: 25),
            CheckboxListTile(
              value: accepted,
              activeColor: gold,
              onChanged: (value) {
                setState(() => accepted = value ?? false);
              },
              title: const Text(
                'I confirm that I am 18 years old or older.',
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: dark,
                ),
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
                child: const Text(
                  'ENTER NIGHTLINK',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '18+ AGE GATE • RESPECT • PRIVACY',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Column(
            children: [
              const Icon(Icons.nightlight_round, color: gold, size: 65),
              const SizedBox(height: 12),
              const Text(
                'NIGHTLINK',
                style: TextStyle(
                  color: gold,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSignup ? 'CREATE YOUR ACCOUNT' : 'WELCOME BACK',
                style: const TextStyle(color: blue, letterSpacing: 2),
              ),
              const SizedBox(height: 35),
              if (isSignup)
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
              if (isSignup) const SizedBox(height: 15),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => obscurePassword = !obscurePassword);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: gold),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: dark,
                  ),
                  onPressed: loading ? null : submit,
                  child: loading
                      ? const CircularProgressIndicator()
                      : Text(
                          isSignup ? 'CREATE ACCOUNT' : 'LOGIN',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 18),
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
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail.trim(),
      queryParameters: {'subject': 'NightLink Support'},
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app is available on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = _profileName ?? user?.userMetadata?['display_name'] ?? 'Member';
    final hideAds = _hasVip || user?.id == 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: dark,
        title: const Text('NIGHTLINK', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: blue),
            onPressed: () async => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 18),
          const Icon(Icons.nightlight_round, color: gold, size: 58),
          const SizedBox(height: 14),
          Text('Welcome, $name!', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('CHOOSE HOW YOU WANT TO CONNECT',
            textAlign: TextAlign.center,
            style: TextStyle(color: blue, letterSpacing: 1, fontWeight: FontWeight.bold)),
          const SizedBox(height: 22),
          _HomeActionCard(
            icon: Icons.person_search,
            title: 'FIND PEOPLE & CONNECTIONS',
            subtitle: 'Edit your username, search members and accept requests',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.play_circle_outline,
            title: 'SHORT VIDEO FEED',
            subtitle: 'Watch, upload and share short videos',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NightLinkFeedScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.auto_awesome,
            title: 'NIGHTLINK AI',
            subtitle: 'Ask questions, get smart help and talk by microphone',
            color: blue,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NightLinkAiScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.chat_bubble_outline,
            title: 'TEXT CHAT',
            subtitle: 'Chat privately with accepted connections',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.mic_none,
            title: 'VOICE CHAT',
            subtitle: 'Talk live with accepted connections',
            color: blue,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.voice))),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.videocam_outlined,
            title: 'VIDEO CHAT',
            subtitle: 'Meet face-to-face with accepted connections',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.video))),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.monetization_on_outlined,
            title: 'COINS & GIFTS',
            subtitle: 'View your coin wallet and gifts',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoinWalletScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.workspace_premium,
            title: 'VIP MEMBERSHIP',
            subtitle: _hasVip ? 'VIP is active on this account' : 'Explore VIP benefits',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VipScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.sports_esports,
            title: 'FIND A MATCH',
            subtitle: '1v1 duels and team battles',
            color: blue,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MatchLobby())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.support_agent,
            title: 'CONTACT US',
            subtitle: 'Send a private message to NightLink support',
            color: blue,
            onTap: _contactUs,
          ),
          if (!_vipLoading)
            NightLinkBannerAd(hide: hideAds),
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
    color: const Color(0xFF11182B),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(.14),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
      onTap: onTap,
    ),
  );
}
