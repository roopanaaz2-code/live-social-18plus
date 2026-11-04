
import 'package:flutter/material.dart';

void main() {
  runApp(const NightLinkApp());
}

const gold = Color(0xFFFFC857);
const blue = Color(0xFF2589FF);
const dark = Color(0xFF090D18);

class NightLinkApp extends StatelessWidget {
  const NightLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NightLink 18+',
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
            const Icon(Icons.nightlight_round,
                color: gold, size: 75),
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
            const SizedBox(height: 45),
            const Text(
              'WELCOME TO THE 18+ COMMUNITY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Meet people, enjoy live conversations, '
              'send messages and compete in exciting '
              'X vs Y battles.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.6),
            ),
            const SizedBox(height: 30),
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
                            builder: (_) => const HomeScreen(),
                          ),
                        );
                      }
                    : null,
                child: const Text(
                  'ENTER NIGHTLINK',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;

  final pages = const [
    ('Discover', Icons.explore),
    ('Messages', Icons.chat),
    ('X vs Y Battles', Icons.bolt),
    ('My Profile', Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: dark,
        title: const Text(
          'NIGHTLINK',
          style: TextStyle(color: gold, fontWeight: FontWeight.bold),
        ),
        actions: const [
          Icon(Icons.notifications_none, color: blue),
          SizedBox(width: 18),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(pages[selected].$2, size: 65, color: gold),
              const SizedBox(height: 20),
              Text(
                pages[selected].$1,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your live social experience starts here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 25),
              if (selected == 2)
                const Text(
                  'PLAYER X  VS  PLAYER Y\n\nLIVE BATTLES COMING SOON',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: blue, height: 2),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF151C2C),
        selectedIndex: selected,
        indicatorColor: blue.withOpacity(0.25),
        onDestinationSelected: (index) {
          setState(() => selected = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt),
            label: 'Battles',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
