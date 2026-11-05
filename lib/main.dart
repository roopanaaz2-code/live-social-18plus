
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'matchmaking.dart';
import 'chat.dart';
import 'live_call.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseKey.isEmpty) {
    runApp(const SetupErrorApp());
    return;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
  );

  runApp(const NightLinkApp());
}

class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        backgroundColor: dark,
        body: Center(
          child: Text(
            'Supabase key is missing.\nCheck GitHub Actions variables.',
            textAlign: TextAlign.center,
            style: TextStyle(color: gold),
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
      title: 'NightLink Live',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: dark,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: blue,
        ),
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
  final _client = Supabase.instance.client;
  RealtimeChannel? _inviteChannel;
  Map<String, dynamic>? _incomingInvite;
  String _callerName = 'NightLink member';
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _loadPendingInvite();
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      _inviteChannel = _client
          .channel('incoming-call-invitations-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'call_invitations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'receiver_id',
              value: userId,
            ),
            callback: (_) => _loadPendingInvite(),
          )
          .subscribe();
    }
  }

  Future<void> _loadPendingInvite() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final invite = await _client
          .from('call_invitations')
          .select('id, caller_id, call_mode, room_name, expires_at')
          .eq('receiver_id', userId)
          .eq('status', 'pending')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at')
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (invite == null) {
        setState(() => _incomingInvite = null);
        return;
      }
      var displayName = 'NightLink member';
      try {
        final profile = await _client
            .from('profiles')
            .select('display_name, username')
            .eq('id', invite['caller_id'])
            .maybeSingle();
        displayName = (profile?['display_name'] ?? profile?['username'] ?? displayName).toString();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _incomingInvite = Map<String, dynamic>.from(invite);
        _callerName = displayName;
      });
    } catch (_) {
      // Keep the home screen usable if realtime or the invitation query is unavailable.
    }
  }

  Future<void> _respondToInvite(bool accept) async {
    final invite = _incomingInvite;
    if (invite == null || _responding) return;
    setState(() => _responding = true);
    try {
      final status = accept ? 'accepted' : 'declined';
      await _client
          .from('call_invitations')
          .update({'status': status})
          .eq('id', invite['id'])
          .eq('status', 'pending');
      if (!mounted) return;
      setState(() => _incomingInvite = null);
      if (accept) {
        final mode = invite['call_mode'] == 'video'
            ? NightLinkCallMode.video
            : NightLinkCallMode.voice;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => LiveCallScreen(
            mode: mode,
            otherName: _callerName,
            roomName: invite['room_name'].toString(),
          ),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not respond to invitation: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  void dispose() {
    final channel = _inviteChannel;
    if (channel != null) _client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['display_name'] ?? 'Member';

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
      body: Stack(\n        children: [\n          ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 18),
          const Icon(Icons.nightlight_round, color: gold, size: 58),
          const SizedBox(height: 14),
          Text('Welcome, $name!', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(user?.email ?? '', textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 12),
          const Text('CHOOSE HOW YOU WANT TO CONNECT',
            textAlign: TextAlign.center,
            style: TextStyle(color: blue, letterSpacing: 1, fontWeight: FontWeight.bold)),
          const SizedBox(height: 22),
          _HomeActionCard(
            icon: Icons.chat_bubble_outline,
            title: 'TEXT CHAT',
            subtitle: 'Send private real-time messages',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.mic_none,
            title: 'VOICE CHAT',
            subtitle: 'Talk live with other members',
            color: blue,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.voice))),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.videocam_outlined,
            title: 'VIDEO CHAT',
            subtitle: 'Meet face-to-face in live rooms',
            color: gold,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.video))),
          ),
          const SizedBox(height: 12),
          _HomeActionCard(
            icon: Icons.sports_esports,
            title: 'FIND A MATCH',
            subtitle: '1v1 duels and team battles',
            color: blue,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MatchLobby())),
          ),
          ],
          ),
          if (_incomingInvite != null)
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Material(
                color: const Color(0xFF182642),
                elevation: 14,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _incomingInvite!['call_mode'] == 'video'
                                ? Icons.videocam
                                : Icons.call,
                            color: gold,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _incomingInvite!['call_mode'] == 'video'
                                  ? 'INCOMING VIDEO CALL'
                                  : 'INCOMING VOICE CALL',
                              style: const TextStyle(
                                color: gold,
                                fontWeight: FontWeight.bold,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$_callerName is inviting you to a ${_incomingInvite!['call_mode']} call.',
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _responding ? null : () => _respondToInvite(false),
                              icon: const Icon(Icons.call_end),
                              label: const Text('DECLINE'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _responding ? null : () => _respondToInvite(true),
                              icon: const Icon(Icons.call),
                              label: const Text('ACCEPT'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: dark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
