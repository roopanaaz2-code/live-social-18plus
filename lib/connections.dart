import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

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

  Widget _section(String title, List<Widget> children) => Card(
    color: const Color(0xFF11182B),
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        ...children,
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(
      backgroundColor: _dark,
      title: const Text('CONNECTIONS', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
      actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, color: _blue))],
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator(color: _gold))
      : _error != null
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            ElevatedButton(onPressed: _load, child: const Text('RETRY')),
          ]))
        : RefreshIndicator(
            color: _gold,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('YOUR PUBLIC PROFILE', [
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _displayName,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Display name'),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _dark),
                      child: const Text('SAVE PROFILE'),
                    ),
                  ),
                  const Text('Other members can find you by username. Your email address is not shown on your public profile.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                _section('FIND MEMBERS', [
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _search,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(hintText: 'Search exact username', prefixText: '@'),
                      onSubmitted: (_) => _searchPeople(),
                    )),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _busy ? null : _searchPeople,
                      style: IconButton.styleFrom(backgroundColor: _blue),
                      icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                    ),
                  ]),
                  for (final person in _results) ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text((person['display_name'] ?? 'Member').toString()),
                    subtitle: Text('@${person['username'] ?? ''}', style: const TextStyle(color: Colors.white54)),
                    trailing: IconButton(
                      tooltip: 'Send connection request',
                      onPressed: _busy ? null : () => _sendRequest(person['username'].toString()),
                      icon: const Icon(Icons.person_add_alt_1, color: _gold),
                    ),
                  ),
                ]),
                _section('INCOMING REQUESTS (${_requests.length})', [
                  if (_requests.isEmpty)
                    const Text('No pending requests.', style: TextStyle(color: Colors.white54))
                  else
                    for (final request in _requests)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.person_add)),
                        title: Text((request['profile']['display_name'] ?? 'Member').toString()),
                        subtitle: Text('@${request['profile']['username'] ?? 'unknown'}'),
                        trailing: Wrap(spacing: 2, children: [
                          IconButton(onPressed: () => _respond(request['id'].toString(), true), icon: const Icon(Icons.check_circle, color: Colors.greenAccent)),
                          IconButton(onPressed: () => _respond(request['id'].toString(), false), icon: const Icon(Icons.cancel, color: Colors.redAccent)),
                        ]),
                      ),
                ]),
                _section('YOUR CONNECTIONS (${_friends.length})', [
                  if (_friends.isEmpty)
                    const Text('No connections yet. Search a username and send a request.',
                      style: TextStyle(color: Colors.white54))
                  else
                    for (final friend in _friends)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.person, color: _blue)),
                        title: Text((friend['display_name'] ?? 'Member').toString()),
                        subtitle: Text('@${friend['username'] ?? ''}'),
                        trailing: const Icon(Icons.verified_user, color: _gold),
                      ),
                ]),
              ],
            ),
          ),
  );
}
