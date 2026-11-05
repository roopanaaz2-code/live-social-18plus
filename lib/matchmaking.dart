import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

enum MatchFormat {
  oneVsOne('1v1', '1 vs 1', 'Head-to-head duel', 2),
  twoVsTwo('2v2', '2 vs 2', 'Team battle', 4),
  fourWay('1v1v1v1', '1v1v1v1', 'Four-player free-for-all', 4);

  const MatchFormat(this.code, this.label, this.description, this.capacity);

  final String code;
  final String label;
  final String description;
  final int capacity;
}

class ActiveMatch {
  const ActiveMatch({
    required this.id,
    required this.mode,
    required this.status,
    required this.maxPlayers,
    required this.playerCount,
    required this.createdAt,
  });

  final String id;
  final String mode;
  final String status;
  final int maxPlayers;
  final int playerCount;
  final DateTime? createdAt;

  factory ActiveMatch.fromMap(Map<String, dynamic> map) {
    return ActiveMatch(
      id: map['match_id'] as String,
      mode: map['mode'] as String,
      status: map['match_status'] as String,
      maxPlayers: (map['max_players'] as num?)?.toInt() ?? 0,
      playerCount: (map['player_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

class QueueResult {
  const QueueResult({
    required this.matched,
    required this.mode,
    required this.playerCount,
    required this.capacity,
    this.matchId,
  });

  final bool matched;
  final String mode;
  final int playerCount;
  final int capacity;
  final String? matchId;

  factory QueueResult.fromMap(Map<String, dynamic> map) {
    return QueueResult(
      matched: map['match_id'] != null,
      mode: map['mode']?.toString() ?? '',
      playerCount: (map['player_count'] as num?)?.toInt() ?? 0,
      capacity: (map['capacity'] as num?)?.toInt() ?? 0,
      matchId: map['match_id']?.toString(),
    );
  }
}

class MatchmakingService {
  MatchmakingService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<QueueResult> join(MatchFormat format) async {
    final response = await _client.rpc(
      'join_matchmaking',
      params: {'p_mode': format.code},
    );
    final rows = _asRows(response);
    if (rows.isEmpty) {
      throw const FormatException('The matchmaking server returned no result.');
    }
    return QueueResult.fromMap(rows.first);
  }

  Future<void> leaveQueue() => _client.rpc('leave_matchmaking');

  Future<ActiveMatch?> activeMatch() async {
    final response = await _client.rpc('get_my_active_match');
    final rows = _asRows(response);
    return rows.isEmpty ? null : ActiveMatch.fromMap(rows.first);
  }

  Future<void> setReady(String matchId) => _client.rpc(
        'set_match_ready',
        params: {'p_match_id': matchId},
      );

  Future<void> leaveMatch(String matchId) => _client.rpc(
        'leave_match',
        params: {'p_match_id': matchId},
      );

  static List<Map<String, dynamic>> _asRows(dynamic response) {
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}

class MatchLobby extends StatefulWidget {
  const MatchLobby({super.key});

  @override
  State<MatchLobby> createState() => _MatchLobbyState();
}

class _MatchLobbyState extends State<MatchLobby> {
  final _service = MatchmakingService();
  Timer? _poller;
  MatchFormat? _searchingFor;
  QueueResult? _queueResult;
  ActiveMatch? _activeMatch;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshMatch();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _refreshMatch());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refreshMatch() async {
    if (!mounted || _busy) return;
    try {
      final match = await _service.activeMatch();
      if (!mounted) return;
      setState(() {
        _activeMatch = match;
        if (match != null) _searchingFor = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _join(MatchFormat format) async {
    setState(() {
      _busy = true;
      _error = null;
      _searchingFor = format;
      _queueResult = null;
      _activeMatch = null;
    });
    try {
      final result = await _service.join(format);
      if (!mounted) return;
      setState(() {
        _queueResult = result;
        if (result.matched) _searchingFor = null;
      });
      await _refreshMatch();
    } catch (error) {
      if (mounted) {
        setState(() {
          _searchingFor = null;
          _error = _friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveQueue() async {
    setState(() => _busy = true);
    try {
      await _service.leaveQueue();
      if (mounted) {
        setState(() {
          _searchingFor = null;
          _queueResult = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ready() async {
    final match = _activeMatch;
    if (match == null) return;
    setState(() => _busy = true);
    try {
      await _service.setReady(match.id);
      await _refreshMatch();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveMatch() async {
    final match = _activeMatch;
    if (match == null) return;
    setState(() => _busy = true);
    try {
      await _service.leaveMatch(match.id);
      if (mounted) setState(() => _activeMatch = null);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = _activeMatch;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MATCHMAKING'),
        backgroundColor: _dark,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          const Text(
            'Choose your format',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Join a live queue and we will create a match when enough players are ready.',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_error != null) _Notice(text: _error!, error: true),
          if (_queueResult != null && _searchingFor != null)
            _QueueCard(
              format: _searchingFor!,
              result: _queueResult!,
              busy: _busy,
              onCancel: _leaveQueue,
            ),
          if (match != null)
            _MatchCard(
              match: match,
              busy: _busy,
              onReady: _ready,
              onLeave: _leaveMatch,
            ),
          for (final format in MatchFormat.values)
            _FormatCard(
              format: format,
              disabled: _busy || _searchingFor != null || match != null,
              onTap: () => _join(format),
            ),
        ],
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) return error.message;
    return 'Matchmaking is temporarily unavailable. Please try again.';
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.format, required this.disabled, required this.onTap});

  final MatchFormat format;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF11182B),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _blue.withOpacity(.18),
          child: Text('${format.capacity}', style: const TextStyle(color: _blue)),
        ),
        title: Text(format.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(format.description, style: const TextStyle(color: Colors.white60)),
        trailing: ElevatedButton(
          onPressed: disabled ? null : onTap,
          child: const Text('PLAY'),
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.format, required this.result, required this.busy, required this.onCancel});

  final MatchFormat format;
  final QueueResult result;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF162442),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Searching ${format.label}', style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${result.playerCount}/${result.capacity} players found', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: result.playerCount / result.capacity, color: _gold),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: busy ? null : onCancel, child: const Text('CANCEL QUEUE')),
        ]),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.busy, required this.onReady, required this.onLeave});

  final ActiveMatch match;
  final bool busy;
  final VoidCallback onReady;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final live = match.status == 'live';
    return Card(
      color: live ? const Color(0xFF173A2B) : const Color(0xFF2D2330),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(live ? 'MATCH LIVE' : 'MATCH FOUND', style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${match.mode}  •  ${match.playerCount}/${match.maxPlayers} players', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          if (!live) ElevatedButton(onPressed: busy ? null : onReady, child: const Text('I AM READY')),
          if (live) const Text('All players are ready. Connect your room to start the game.', style: TextStyle(color: Colors.white70)),
          TextButton(onPressed: busy ? null : onLeave, child: const Text('LEAVE MATCH')),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (error ? Colors.red : _gold).withOpacity(.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: error ? Colors.redAccent : _gold)),
    );
  }
}
