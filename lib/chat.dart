import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connections.dart';
import 'nightlink_design.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _loadPeople(); }

  Future<void> _loadPeople() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    try {
      final links = await _db.from('friendships')
          .select('user_low_id, user_high_id')
          .or('user_low_id.eq.${user.id},user_high_id.eq.${user.id}');
      final ids = (links as List).map((row) {
        final low = row['user_low_id'].toString();
        final high = row['user_high_id'].toString();
        return low == user.id ? high : low;
      }).toList();
      final rows = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await _db.from('profiles')
              .select('id, username, display_name, avatar_url')
              .inFilter('id', ids).order('display_name');
      if (!mounted) return;
      setState(() {
        _people = List<Map<String, dynamic>>.from(rows);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load members. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          NightLinkDesign.eyebrow('Stay connected'),
          const SizedBox(height: 2),
          const Text('Messages'),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Find members',
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
            _loadPeople();
          },
          icon: const Icon(Icons.person_search_rounded),
        ),
        IconButton(
          tooltip: 'Refresh conversations',
          onPressed: _loadPeople,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: NightLinkPanel(
              accent: NightLinkDesign.error,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, color: NightLinkDesign.error, size: 34),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: NightLinkDesign.textMuted, height: 1.45)),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _loadPeople, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
              ]),
            ),
          ))
        : _people.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(28),
              child: NightLinkPanel(
                gradient: true,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: NightLinkDesign.blue.withOpacity(.12), shape: BoxShape.circle),
                    child: const Icon(Icons.forum_rounded, color: NightLinkDesign.blue, size: 30),
                  ),
                  const SizedBox(height: 18),
                  const Text('Your conversations start here', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Find members and connect to start a private conversation.', textAlign: TextAlign.center, style: TextStyle(color: NightLinkDesign.textMuted, height: 1.5)),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
                      _loadPeople();
                    },
                    icon: const Icon(Icons.person_search_rounded),
                    label: const Text('Find members'),
                  ),
                ]),
              ),
            ))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              itemCount: _people.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final person = _people[index];
                final name = (person['display_name'] ?? person['username'] ?? 'NightLink member').toString();
                final username = (person['username'] ?? '').toString();
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(NightLinkDesign.radius),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ConversationScreen(otherUserId: person['id'].toString(), otherName: name),
                    )),
                    child: Ink(
                      decoration: NightLinkDesign.surfaceDecoration(accent: NightLinkDesign.blue),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          NightLinkDesign.avatar(
                            name: name,
                            imageUrl: person['avatar_url']?.toString(),
                            radius: 27,
                            accent: NightLinkDesign.blue,
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(username.isEmpty ? 'Private conversation' : '@$username', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13)),
                            ],
                          )),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios_rounded, color: NightLinkDesign.gold, size: 17),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
  );
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.otherUserId, required this.otherName});
  final String otherUserId;
  final String otherName;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _db = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  bool _loadingMessages = false;
  Timer? _refreshTimer;
  String? _error;
  String get _myId => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _channel = _db.channel('private-chat-' + _myId + '-' + widget.otherUserId)
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => _loadMessages(),
      ).subscribe();
    // Realtime is primary; low-frequency refresh recovers if Android suspends
    // the WebSocket while the app is backgrounded or the network changes.
    _refreshTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted && !_loadingMessages) _loadMessages();
    });
  }

  Future<void> _loadMessages() async {
    if (_loadingMessages) return;
    _loadingMessages = true;
    try {
      final filter = 'and(sender_id.eq.' + _myId + ',receiver_id.eq.' + widget.otherUserId +
        '),and(sender_id.eq.' + widget.otherUserId + ',receiver_id.eq.' + _myId + ')';
      final rows = await _db.from('messages')
        .select('id, sender_id, receiver_id, content, created_at')
        .or(filter).order('created_at');
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(rows);
        _loading = false;
        _loadingMessages = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMessages = false;
        _error = 'Messages could not be loaded: $error';
      });
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _db.from('messages').insert({
        'sender_id': _myId,
        'receiver_id': widget.otherUserId,
        'content': body,
      });
      _input.clear();
      await _loadMessages();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message was not sent: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _refreshTimer?.cancel();
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }

  String _timeLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 4,
      title: Row(children: [
        NightLinkDesign.avatar(name: widget.otherName, radius: 20, accent: NightLinkDesign.blue),
        const SizedBox(width: 11),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.otherName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text('Private conversation', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        )),
      ]),
    ),
    body: Column(children: [
      if (_error != null) Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: NightLinkPanel(
          accent: NightLinkDesign.error,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          radius: 14,
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: NightLinkDesign.error, size: 19),
            const SizedBox(width: 9),
            Expanded(child: Text(_error!, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13))),
          ]),
        ),
      ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _messages.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(color: NightLinkDesign.blue.withOpacity(.12), shape: BoxShape.circle),
                  child: const Icon(Icons.waving_hand_rounded, color: NightLinkDesign.gold, size: 28),
                ),
                const SizedBox(height: 16),
                const Text('A simple hello goes a long way', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                const Text('Send the first message to start your conversation.', textAlign: TextAlign.center, style: TextStyle(color: NightLinkDesign.textMuted, height: 1.45)),
              ]),
            ))
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final row = _messages[index];
                final mine = row['sender_id'] == _myId;
                final timestamp = _timeLabel(row['created_at']);
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.fromLTRB(15, 11, 15, 9),
                    decoration: BoxDecoration(
                      gradient: mine ? const LinearGradient(
                        colors: [Color(0xFF2455A0), Color(0xFF183A70)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ) : null,
                      color: mine ? null : NightLinkDesign.surfaceRaised,
                      border: Border.all(color: mine ? NightLinkDesign.blue.withOpacity(.32) : Colors.white.withOpacity(.06)),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(19),
                        topRight: const Radius.circular(19),
                        bottomLeft: Radius.circular(mine ? 19 : 5),
                        bottomRight: Radius.circular(mine ? 5 : 19),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(row['content'].toString(), style: const TextStyle(color: NightLinkDesign.text, height: 1.35, fontSize: 15)),
                        ),
                        if (timestamp.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(timestamp, style: TextStyle(color: Colors.white.withOpacity(.64), fontSize: 10, letterSpacing: .2)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            )),
      SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: _input, minLines: 1, maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: 'Write a message...',
              prefixIcon: Icon(Icons.chat_bubble_outline_rounded, size: 19),
              contentPadding: EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            ),
          )),
          const SizedBox(width: 9),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filled(
              tooltip: 'Send message',
              onPressed: _sending ? null : _send,
              style: IconButton.styleFrom(backgroundColor: NightLinkDesign.gold, foregroundColor: NightLinkDesign.background),
              icon: _sending
                ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            ),
          ),
        ]),
      )),
    ]),
  );
}
