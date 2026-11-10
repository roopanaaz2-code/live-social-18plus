import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle_room.dart';
import 'nightlink_design.dart';

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

  Future<List<Map<String, dynamic>>> liveBattles() async {
    final response = await _client.rpc('get_live_battles');
    return _asRows(response);
  }

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
  List<Map<String, dynamic>> _liveBattles = [];
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
      final results = await Future.wait([_service.activeMatch(), _service.liveBattles()]);
      final match = results[0] as ActiveMatch?;
      final liveBattles = results[1] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        _activeMatch = match;
        _liveBattles = liveBattles;
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

  void _enterBattle(String matchId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BattleRoomScreen(matchId: matchId),
    )).then((_) => _refreshMatch());
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
      appBar: AppBar(title: const Text('Battle lobby'), backgroundColor: NightLinkDesign.background),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        children: [
          NightLinkPanel(
            accent: NightLinkDesign.gold,
            gradient: true,
            padding: const EdgeInsets.all(21),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: NightLinkDesign.gold.withOpacity(.14),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.sports_mma_rounded, color: NightLinkDesign.gold),
                ),
                const SizedBox(width: 12),
                NightLinkDesign.eyebrow('NightLink arena', color: NightLinkDesign.gold),
              ]),
              const SizedBox(height: 15),
              const Text('Choose your battle', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              const Text('Pick a format and enter the live queue. We’ll bring the players together when the lobby is ready.',
                  style: TextStyle(color: NightLinkDesign.textMuted, height: 1.45)),
            ]),
          ),
          const SizedBox(height: 20),
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
              onEnter: () => _enterBattle(match.id),
            ),
          if (_liveBattles.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 9),
              child: Row(children: [
                const Icon(Icons.wifi_tethering_rounded, size: 17, color: NightLinkDesign.error),
                const SizedBox(width: 8),
                NightLinkDesign.eyebrow('Live now', color: NightLinkDesign.gold),
                const Spacer(),
                Text('${_liveBattles.length} battles', style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
              ]),
            ),
            for (final battle in _liveBattles)
              if (battle['match_id']?.toString() != match?.id)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(NightLinkDesign.radius),
                      onTap: () => _enterBattle(battle['match_id'].toString()),
                      child: NightLinkPanel(
                        accent: NightLinkDesign.error,
                        padding: const EdgeInsets.all(15),
                        child: Row(children: [
                          Container(width: 44, height: 44,
                            decoration: BoxDecoration(color: NightLinkDesign.error.withOpacity(.12),
                                borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.live_tv_rounded, color: NightLinkDesign.error)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${battle['mode'] ?? 'PK'} battle', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('${(battle['players'] as List? ?? []).length} players • watch, comment and send gifts',
                                style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 11)),
                          ])),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, color: NightLinkDesign.gold),
                        ]),
                      ),
                    ),
                  ),
                ),
          ],
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
    final icon = format.capacity == 2
        ? Icons.person_rounded
        : format.code == '2v2' ? Icons.groups_rounded : Icons.grid_view_rounded;
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF203A59), Color(0xFF17233A)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: NightLinkDesign.blue.withOpacity(.24)),
            ),
            child: Icon(icon, color: NightLinkDesign.blue, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(format.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(format.description, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
            const SizedBox(height: 7),
            Text('${format.capacity} players', style: const TextStyle(color: NightLinkDesign.blue, fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: disabled ? null : onTap,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12)),
            child: const Text('JOIN'),
          ),
        ]),
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
    return NightLinkPanel(
      accent: NightLinkDesign.gold,
      gradient: true,
      padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(width: 42, height: 42,
              child: CircularProgressIndicator(color: NightLinkDesign.gold, strokeWidth: 3)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Finding ${format.label}', style: const TextStyle(color: NightLinkDesign.gold, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${result.playerCount}/${result.capacity} players found', style: const TextStyle(color: NightLinkDesign.textMuted)),
            ])),
          ]),
          const SizedBox(height: 17),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
            value: result.capacity == 0 ? 0.0 : (result.playerCount / result.capacity).clamp(0.0, 1.0).toDouble(),
            color: NightLinkDesign.gold, backgroundColor: Colors.white10, minHeight: 7,
          )),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: busy ? null : onCancel, child: const Text('Cancel search'))),
        ]),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.busy, required this.onReady, required this.onLeave, required this.onEnter});

  final ActiveMatch match;
  final bool busy;
  final VoidCallback onReady;
  final VoidCallback onLeave;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final live = match.status == 'live';
    return NightLinkPanel(
      accent: live ? NightLinkDesign.success : NightLinkDesign.gold,
      gradient: true,
      padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(live ? Icons.wifi_tethering_rounded : Icons.check_circle_outline_rounded,
                color: live ? NightLinkDesign.success : NightLinkDesign.gold, size: 21),
            const SizedBox(width: 8),
            Text(live ? 'MATCH LIVE' : 'MATCH FOUND',
                style: TextStyle(color: live ? NightLinkDesign.success : NightLinkDesign.gold,
                    fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .9)),
          ]),
          const SizedBox(height: 9),
          Text(match.mode, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text('${match.playerCount}/${match.maxPlayers} players in lobby', style: const TextStyle(color: NightLinkDesign.textMuted)),
          const SizedBox(height: 14),
          if (!live) SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: busy ? null : onReady,
            icon: const Icon(Icons.done_rounded),
            label: const Text('I’m ready'),
          )),
          if (live) SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: busy ? null : onEnter,
            icon: const Icon(Icons.videocam),
            label: const Text('Enter live battle'),
          )),
          Center(child: TextButton(onPressed: busy ? null : onLeave, child: const Text('Leave match'))),
        ]),
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
