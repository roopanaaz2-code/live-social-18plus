import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

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
      final rows = await _db.from('profiles')
          .select('id, username, display_name, avatar_url')
          .neq('id', user.id).order('display_name');
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
    backgroundColor: _dark,
    appBar: AppBar(
      backgroundColor: _dark,
      title: const Text('TEXT CHAT', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
      actions: [IconButton(onPressed: _loadPeople, icon: const Icon(Icons.refresh, color: _blue))],
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator(color: _gold))
      : _error != null
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            ElevatedButton(onPressed: _loadPeople, child: const Text('RETRY')),
          ]))
        : _people.isEmpty
          ? const Center(child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('No other members are available yet. Invite someone to create a NightLink account, then refresh.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
            ))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _people.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final person = _people[index];
                final name = (person['display_name'] ?? person['username'] ?? 'NightLink member').toString();
                return Card(
                  color: const Color(0xFF11182B),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0x332589FF), child: Icon(Icons.person, color: _blue)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Open private conversation', style: TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.chevron_right, color: _gold),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ConversationScreen(otherUserId: person['id'].toString(), otherName: name),
                    )),
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
  }

  Future<void> _loadMessages() async {
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
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Messages could not be loaded. Check your connection.'; });
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message was not sent. Please try again.')),
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
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(backgroundColor: _dark, title: Text(widget.otherName)),
    body: Column(children: [
      if (_error != null) Padding(
        padding: const EdgeInsets.all(8),
        child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
      ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: _gold))
        : _messages.isEmpty
          ? const Center(child: Text('Say hello to start the conversation.', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final row = _messages[index];
                final mine = row['sender_id'] == _myId;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFF17365D) : const Color(0xFF20283A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(row['content'].toString(), style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            )),
      SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _input, minLines: 1, maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Write a message...', filled: true,
              fillColor: const Color(0xFF151E31),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          )),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(backgroundColor: _gold, foregroundColor: _dark),
            icon: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          ),
        ]),
      )),
    ]),
  );
}
