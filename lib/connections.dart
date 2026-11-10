import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nightlink_design.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _db = Supabase.instance.client;
  final _search = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _myId => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final profile = await _db.from('profiles')
          .select('username, display_name')
          .eq('id', _myId).maybeSingle();
      _username.text = (profile?['username'] ?? '').toString();
      _displayName.text = (profile?['display_name'] ?? '').toString();

      final friendshipRows = await _db.from('friendships')
          .select('user_low_id, user_high_id')
          .or('user_low_id.eq.$_myId,user_high_id.eq.$_myId');
      final friendIds = (friendshipRows as List).map((row) {
        final low = row['user_low_id'].toString();
        final high = row['user_high_id'].toString();
        return low == _myId ? high : low;
      }).toList();

      final requestRows = await _db.from('friend_requests')
          .select('id, sender_id, created_at')
          .eq('receiver_id', _myId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final allIds = <String>{
        ...friendIds,
        ...requestRows.map((row) => row['sender_id'].toString()),
      }.toList();

      List<Map<String, dynamic>> profiles = [];
      if (allIds.isNotEmpty) {
        final rows = await _db.from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', allIds);
        profiles = List<Map<String, dynamic>>.from(rows);
      }
      final byId = {for (final p in profiles) p['id'].toString(): p};

      if (!mounted) return;
      setState(() {
        _friends = friendIds.map((id) => byId[id])
            .whereType<Map<String, dynamic>>().toList();
        _requests = requestRows.map((row) {
          final profile = byId[row['sender_id'].toString()] ?? <String, dynamic>{};
          return {...Map<String, dynamic>.from(row), 'profile': profile};
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load connections. Check your internet and try again.'; });
    }
  }

  Future<void> _searchPeople() async {
    final term = _search.text.trim().replaceFirst(RegExp(r'^@'), '');
    if (term.length < 3) {
      _message('Enter at least 3 characters of a username.');
      return;
    }
    setState(() { _busy = true; _results = []; });
    try {
      final rows = await _db.from('profiles')
          .select('id, username, display_name, avatar_url')
          .ilike('username', term)
          .neq('id', _myId)
          .limit(15);
      if (!mounted) return;
      setState(() => _results = List<Map<String, dynamic>>.from(rows));
      if (_results.isEmpty) _message('No member found. Check the exact username.');
    } catch (_) {
      _message('Search failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendRequest(String username) async {
    try {
      await _db.rpc('send_friend_request', params: {'p_username': username});
      _message('Connection request sent.');
      if (mounted) setState(() => _results.removeWhere((p) => p['username'] == username));
      await _load();
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _respond(String requestId, bool accept) async {
    try {
      await _db.rpc('respond_friend_request', params: {
        'p_request_id': requestId,
        'p_accept': accept,
      });
      _message(accept ? 'Request accepted. You are now connected.' : 'Request declined.');
      await _load();
    } catch (_) {
      _message('Could not update this request. Refresh and try again.');
    }
  }

  Future<void> _saveProfile() async {
    final username = _username.text.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    final displayName = _displayName.text.trim();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(username)) {
      _message('Username must be 3-24 characters: letters, numbers or underscores.');
      return;
    }
    if (displayName.isEmpty || displayName.length > 40) {
      _message('Display name must be 1-40 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _db.from('profiles').update({
        'username': username,
        'display_name': displayName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _myId);
      _message('Your profile was updated.');
      await _load();
    } on PostgrestException catch (error) {
      _message(error.code == '23505' ? 'That username is already taken.' : 'Could not save profile: ${error.message}');
    } catch (_) {
      _message('Could not save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    _search.dispose();
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Widget _section(String title, String description, List<Widget> children, {Color accent = NightLinkDesign.gold}) =>
      NightLinkPanel(
        accent: accent,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NightLinkDesign.eyebrow(title, color: accent),
                const SizedBox(height: 5),
                Text(description, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12, height: 1.4)),
              ],
            )),
          ]),
          const SizedBox(height: 16),
          ...children,
        ]),
      );

  Widget _personRow({
    required Map<String, dynamic> person,
    required Widget trailing,
    Color accent = NightLinkDesign.blue,
    String? fallbackName,
  }) {
    final name = (person['display_name'] ?? fallbackName ?? 'Member').toString();
    final username = (person['username'] ?? 'unknown').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        NightLinkDesign.avatar(
          name: name,
          imageUrl: person['avatar_url']?.toString(),
          radius: 23,
          accent: accent,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 3),
            Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
          ],
        )),
        const SizedBox(width: 6),
        trailing,
      ]),
    );
  }

  Widget _emptyMessage(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, color: NightLinkDesign.textMuted, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 13, height: 1.4))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          NightLinkDesign.eyebrow('Your circle'),
          const SizedBox(height: 2),
          const Text('Connections'),
        ],
      ),
      actions: [IconButton(
        tooltip: 'Refresh connections',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh_rounded),
      )],
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
                ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
              ]),
            ),
          ))
        : RefreshIndicator(
            color: NightLinkDesign.gold,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _section('Your public profile', 'Make it easy for people to recognize and find you.', [
                  Row(children: [
                    NightLinkDesign.avatar(name: _displayName.text.isEmpty ? 'You' : _displayName.text, radius: 27, accent: NightLinkDesign.gold),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Your profile is visible to other members.', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 13, height: 1.4))),
                  ]),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Username', prefixText: '@', prefixIcon: Icon(Icons.alternate_email_rounded)),
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayName,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _saveProfile,
                      icon: _busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                      label: const Text('Save profile'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Your email address is never shown on your public profile.', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12, height: 1.4)),
                ], accent: NightLinkDesign.gold),
                const SizedBox(height: 14),
                _section('Find members', 'Search by exact username to send a connection request.', [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: TextField(
                      controller: _search,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(hintText: 'Search username', prefixText: '@', prefixIcon: Icon(Icons.search_rounded)),
                      onSubmitted: (_) => _searchPeople(),
                    )),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: IconButton.filled(
                        tooltip: 'Search members',
                        onPressed: _busy ? null : _searchPeople,
                        style: IconButton.styleFrom(backgroundColor: NightLinkDesign.blue, foregroundColor: NightLinkDesign.text),
                        icon: _busy ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded),
                      ),
                    ),
                  ]),
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final person in _results)
                      _personRow(
                        person: person,
                        accent: NightLinkDesign.blue,
                        trailing: IconButton.filledTonal(
                          tooltip: 'Send connection request',
                          onPressed: _busy ? null : () => _sendRequest(person['username'].toString()),
                          style: IconButton.styleFrom(foregroundColor: NightLinkDesign.gold, backgroundColor: NightLinkDesign.gold.withOpacity(.12)),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                        ),
                      ),
                  ],
                ], accent: NightLinkDesign.blue),
                const SizedBox(height: 14),
                _section('Incoming requests', 'People who would like to connect with you.', [
                  if (_requests.isEmpty)
                    _emptyMessage(Icons.mark_email_read_outlined, 'No pending requests right now.'),
                  for (final request in _requests)
                    _personRow(
                      person: Map<String, dynamic>.from(request['profile'] as Map),
                      fallbackName: 'Member',
                      accent: NightLinkDesign.gold,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton.filledTonal(
                          tooltip: 'Accept request',
                          onPressed: () => _respond(request['id'].toString(), true),
                          style: IconButton.styleFrom(foregroundColor: NightLinkDesign.success, backgroundColor: NightLinkDesign.success.withOpacity(.12)),
                          icon: const Icon(Icons.check_rounded),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'Decline request',
                          onPressed: () => _respond(request['id'].toString(), false),
                          style: IconButton.styleFrom(foregroundColor: NightLinkDesign.error, backgroundColor: NightLinkDesign.error.withOpacity(.12)),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ]),
                    ),
                ], accent: NightLinkDesign.gold),
                const SizedBox(height: 14),
                _section('Your connections', 'Your accepted connections are ready to chat.', [
                  if (_friends.isEmpty)
                    _emptyMessage(Icons.people_outline_rounded, 'No connections yet. Search for a username above to get started.'),
                  for (final friend in _friends)
                    _personRow(
                      person: friend,
                      accent: NightLinkDesign.blue,
                      trailing: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: NightLinkDesign.success.withOpacity(.1), shape: BoxShape.circle),
                        child: const Icon(Icons.verified_rounded, color: NightLinkDesign.success, size: 20),
                      ),
                    ),
                ], accent: NightLinkDesign.blue),
              ],
            ),
          ),
  );
}
