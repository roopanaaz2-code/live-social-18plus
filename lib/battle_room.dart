import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'nightlink_design.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

class BattleRoomScreen extends StatefulWidget {
  const BattleRoomScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<BattleRoomScreen> createState() => _BattleRoomScreenState();
}

class _BattleRoomScreenState extends State<BattleRoomScreen> {
  final _db = Supabase.instance.client;
  final _commentController = TextEditingController();
  Room? _room;
  RealtimeChannel? _channel;
  Timer? _clock;
  Timer? _giftBannerTimer;
  Timer? _scoreDeltaTimer;
  DateTime? _endsAt;
  Duration _remaining = const Duration(minutes: 4);
  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _scores = [];
  final Map<int, int> _scoreDeltas = {};
  List<Map<String, dynamic>> _profileLikes = [];
  List<Map<String, dynamic>> _gifts = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _giftEvents = [];
  Map<String, dynamic>? _winner;
  Map<String, dynamic>? _giftBanner;
  String? _selectedRecipientId;
  String? _error;
  bool _connecting = true;
  bool _isPlayer = false;
  bool _sendingComment = false;
  bool _finishing = false;
  bool _finishErrorShown = false;
  bool _micEnabled = false;
  bool _cameraEnabled = false;

  String get _myId => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final access = await _db.rpc(
        'get_battle_access',
        params: {'p_match_id': widget.matchId},
      );
      if (access is! List || access.isEmpty) {
        throw Exception('This battle is no longer available.');
      }
      final accessRow = Map<String, dynamic>.from(access.first as Map);
      _isPlayer = accessRow['is_player'] == true;
      _endsAt = DateTime.tryParse(accessRow['battle_ends_at']?.toString() ?? '');

      await _loadData();
      _subscribe();

      final response = await _db.functions.invoke(
        'generate-livekit-token',
        body: {'matchId': widget.matchId},
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        throw Exception(data is Map
            ? (data['error']?.toString() ?? 'Could not join the live room.')
            : 'Could not join the live room.');
      }
      final token = data['token']?.toString();
      final serverUrl = data['serverUrl']?.toString();
      if (token == null || token.isEmpty || serverUrl == null || serverUrl.isEmpty) {
        throw Exception('Live room connection details are incomplete.');
      }

      final room = Room();
      _room = room;
      room.addListener(_onRoomChanged);
      await room.connect(
        serverUrl,
        token,
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: const AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            highPassFilter: true,
            voiceIsolation: true,
            typingNoiseDetection: true,
          ),
        ),
      );
      // Live battles are video rooms, so route audio to the loudspeaker.
      // Echo cancellation and noise suppression above help reduce feedback.
      await AudioManager.instance.setSpeakerOutputPreferred(true);
      if (_isPlayer) {
        await room.localParticipant?.setMicrophoneEnabled(true);
        await room.localParticipant?.setCameraEnabled(true);
      }

      if (!mounted) return;
      setState(() {
        _connecting = false;
        _micEnabled = _isPlayer;
        _cameraEnabled = _isPlayer;
      });
      _updateClock();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadData() async {
    final live = await _db.rpc('get_live_battles');
    final liveRows = (live as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final battle = liveRows.where((row) => row['match_id'].toString() == widget.matchId);
    if (battle.isNotEmpty) {
      final row = battle.first;
      _players = (row['players'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _scores = (row['scores'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _endsAt ??= DateTime.tryParse(row['battle_ends_at']?.toString() ?? '');
    }

    final results = await Future.wait([
      _db.from('gift_catalog')
          .select('gift_key, display_name, emoji, coin_cost, score_value, is_free')
          .eq('active', true).order('coin_cost'),
      _db.from('battle_comments').select('id, user_id, display_name, content, created_at')
          .eq('match_id', widget.matchId).order('created_at', ascending: false).limit(35),
      _db.from('battle_gifts')
          .select('id, sender_id, recipient_id, team_no, gift_key, quantity, score_added, sender_name, recipient_name, gift_name, gift_emoji, created_at')
          .eq('match_id', widget.matchId).order('created_at', ascending: false).limit(20),
      _db.from('battle_scores').select('team_no, score').eq('match_id', widget.matchId),
    ]);
    _gifts = (results[0] as List).cast<Map<String, dynamic>>();
    _comments = (results[1] as List).cast<Map<String, dynamic>>().reversed.toList();
    _giftEvents = (results[2] as List).cast<Map<String, dynamic>>();
    _scores = (results[3] as List).cast<Map<String, dynamic>>();
    final playerIds = _players.map((p) => p['user_id'].toString()).toList();
    _profileLikes = playerIds.isEmpty
        ? []
        : List<Map<String, dynamic>>.from(await _db.from('profile_likes')
            .select('profile_id, viewer_id').inFilter('profile_id', playerIds));
    if (_selectedRecipientId == null && _players.isNotEmpty) {
      _selectedRecipientId = _players.first['user_id']?.toString();
      if (_selectedRecipientId == _myId && _players.length > 1) {
        _selectedRecipientId = _players[1]['user_id']?.toString();
      }
    }
  }

  void _subscribe() {
    _channel = _db.channel('battle-room-${widget.matchId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'battle_comments',
        callback: (_) => _refreshData(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'battle_gifts',
        callback: (payload) {
          _refreshData();
          final row = payload.newRecord;
          if (mounted && row['match_id']?.toString() == widget.matchId) {
            setState(() => _giftBanner = Map<String, dynamic>.from(row));
            _giftBannerTimer?.cancel();
            _giftBannerTimer = Timer(const Duration(seconds: 4), () {
              if (mounted) setState(() => _giftBanner = null);
            });
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'battle_scores',
        callback: (_) => _refreshData(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'profile_likes',
        callback: (_) => _refreshData(),
      )
      .subscribe();
  }

  Future<void> _refreshData() async {
    try {
      final previousScores = <int, int>{
        for (final row in _scores)
          (row['team_no'] as num?)?.toInt() ?? 1:
              (row['score'] as num?)?.toInt() ?? 0,
      };
      await _loadData();
      final deltas = <int, int>{};
      for (final row in _scores) {
        final team = (row['team_no'] as num?)?.toInt() ?? 1;
        final next = (row['score'] as num?)?.toInt() ?? 0;
        final before = previousScores[team];
        if (before != null && next != before) deltas[team] = next - before;
      }
      if (!mounted) return;
      setState(() {
        _scoreDeltas
          ..clear()
          ..addAll(deltas);
      });
      _scoreDeltaTimer?.cancel();
      if (deltas.isNotEmpty) {
        _scoreDeltaTimer = Timer(const Duration(milliseconds: 2200), () {
          if (mounted) setState(_scoreDeltas.clear);
        });
      }
    } catch (_) {}
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  void _updateClock() {
    final end = _endsAt;
    if (end == null || !mounted) return;
    final remaining = end.difference(DateTime.now());
    setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
    if (remaining <= Duration.zero && !_finishing && _winner == null) {
      _finishBattle();
    }
  }

  Future<void> _finishBattle() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final result = await _db.rpc(
        'finish_battle',
        params: {'p_match_id': widget.matchId},
      );
      if (!mounted) return;
      if (result is Map) {
        setState(() => _winner = Map<String, dynamic>.from(result));
      }
      await _refreshData();
    } catch (error) {
      final message = error.toString();
      if (mounted && !message.toLowerCase().contains('timer has not finished') && !_finishErrorShown) {
        _finishErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finalize battle yet: $error')),
        );
      }
    } finally {
      _finishing = false;
    }
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      await _db.rpc('add_battle_comment', params: {
        'p_match_id': widget.matchId,
        'p_content': content,
      });
      _commentController.clear();
      await _refreshData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Comment not sent: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _doubleTapLike(String hostId) async {
    if (hostId == _myId) return;
    try {
      final result = await _db.rpc('add_battle_like', params: {
        'p_match_id': widget.matchId,
        'p_host_id': hostId,
      });
      await _refreshData();
      if (!mounted) return;
      final added = result is Map && result['profile_like_added'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text(added ? '❤️ Profile liked' : 'Profile like was not recorded'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Like failed: $error')),
        );
      }
    }
  }

  bool get _isDeveloper =>
      _db.auth.currentUser?.id == 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd';

  Future<void> _showGiftPicker() async {
    if (_players.isEmpty) return;
    final balanceRow = await _db.from('coin_wallets')
        .select('balance').eq('user_id', _myId).maybeSingle();
    final balance = (balanceRow?['balance'] as num?)?.toInt() ?? 0;
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11182B),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('SEND A BATTLE GIFT', style: TextStyle(color: _gold, fontWeight: FontWeight.bold))),
                  Text(_isDeveloper ? 'DEVELOPER VIP • GIFTS FREE' : '$balance coins', style: const TextStyle(color: _blue, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRecipientId,
                decoration: const InputDecoration(labelText: 'Send to host'),
                dropdownColor: const Color(0xFF17233A),
                items: _players
                    .where((p) => !_isPlayer || p['user_id'].toString() != _myId)
                    .map((p) => DropdownMenuItem(
                      value: p['user_id'].toString(),
                      child: Text((p['display_name'] ?? 'Host').toString()),
                    )).toList(),
                onChanged: (value) => setState(() => _selectedRecipientId = value),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: _gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, childAspectRatio: 1.08,
                    crossAxisSpacing: 8, mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, index) {
                    final gift = _gifts[index];
                    final free = gift['is_free'] == true;
                    final cost = (gift['coin_cost'] as num).toInt();
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: (!free && !_isDeveloper && balance < cost) ? null : () async {
                        Navigator.pop(sheetContext);
                        await _sendGift(gift);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2740),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _blue.withOpacity(.25)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(gift['emoji'].toString(), style: const TextStyle(fontSize: 28)),
                            const SizedBox(height: 4),
                            Text(gift['display_name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white)),
                            Text((free || _isDeveloper) ? 'FREE' : '$cost coins',
                              style: TextStyle(fontSize: 10, color: (!free && !_isDeveloper && balance < cost) ? Colors.redAccent : _gold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendGift(Map<String, dynamic> gift) async {
    final recipient = _selectedRecipientId;
    if (recipient == null) return;
    try {
      await _db.rpc('send_battle_gift', params: {
        'p_match_id': widget.matchId,
        'p_recipient_id': recipient,
        'p_gift_key': gift['gift_key'],
        'p_quantity': 1,
      });
      await _refreshData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gift not sent: $error')),
        );
      }
    }
  }

  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null || !_isPlayer) return;
    final next = !_micEnabled;
    await room.localParticipant?.setMicrophoneEnabled(next);
    if (mounted) setState(() => _micEnabled = next);
  }

  Future<void> _toggleCamera() async {
    final room = _room;
    if (room == null || !_isPlayer) return;
    final next = !_cameraEnabled;
    await room.localParticipant?.setCameraEnabled(next);
    if (mounted) setState(() => _cameraEnabled = next);
  }

  Widget _playerTile(Map<String, dynamic> player) {
    final userId = player['user_id'].toString();
    final isMe = userId == _myId;
    VideoTrack? videoTrack;
    if (isMe) {
      final publications = _room?.localParticipant?.videoTrackPublications ?? [];
      for (final publication in publications) {
        final track = publication.track;
        if (track is VideoTrack && !publication.muted) {
          videoTrack = track;
          break;
        }
      }
    } else {
      final remoteParticipant = _room?.remoteParticipants[userId];
      final publications = remoteParticipant?.videoTrackPublications ?? [];
      for (final publication in publications) {
        final track = publication.track;
        if (track is VideoTrack && !publication.muted) {
          videoTrack = track;
          break;
        }
      }
    }

    final team = (player['team_no'] as num?)?.toInt() ?? 1;
    final score = _teamScore(team);
    return GestureDetector(
      onTap: () {
        if (!_isPlayer || userId != _myId) {
          setState(() => _selectedRecipientId = userId);
        }
      },
      onDoubleTap: () => _doubleTapLike(userId),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1A2B45), Color(0xFF101725)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: videoTrack == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NightLinkDesign.avatar(
                          name: (player['display_name'] ?? 'Host').toString(),
                          imageUrl: player['avatar_url']?.toString(),
                          radius: 31,
                          accent: NightLinkDesign.blue,
                        ),
                        const SizedBox(height: 6),
                        Text((player['display_name'] ?? 'Host').toString(),
                          style: const TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w600)),
                        const Text('Connecting camera…', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 10)),
                      ],
                    )
                  : VideoTrackRenderer(videoTrack),
            ),
            Positioned(
              left: 8, right: 8, bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.72),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(
                      '${player['display_name'] ?? 'Host'}${isMe ? ' • YOU' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    )),
                    const SizedBox(width: 6),
                    const Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 13),
                    Text('${_hostLikeCount(userId)}', style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text('$score pts', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            if (_selectedRecipientId == userId)
              Positioned(
                top: 9, right: 9,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: NightLinkDesign.gold.withOpacity(.2),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.card_giftcard_rounded, color: NightLinkDesign.gold, size: 17),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<int> get _teamNumbers {
    final teams = _scores.map((row) => (row['team_no'] as num?)?.toInt() ?? 1).toSet().toList()..sort();
    return teams.isEmpty ? [1, 2] : teams;
  }

  int _hostLikeCount(String hostId) => _profileLikes.where((row) => row['profile_id'].toString() == hostId).length;

  int _teamScore(int team) {
    for (final row in _scores) {
      if ((row['team_no'] as num?)?.toInt() == team) {
        return (row['score'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  int get _maxTeamScore {
    var highest = 1;
    for (final row in _scores) {
      final score = (row['score'] as num?)?.toInt() ?? 0;
      if (score > highest) highest = score;
    }
    return highest;
  }

  String _timerText() {
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _leave() async {
    _clock?.cancel();
    final room = _room;
    _room = null;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      await room.disconnect();
      await room.dispose();
    }
    if (_isPlayer) {
      try {
        await _db.rpc('leave_match', params: {'p_match_id': widget.matchId});
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _giftBannerTimer?.cancel();
    _scoreDeltaTimer?.cancel();
    _commentController.dispose();
    if (_channel != null) _db.removeChannel(_channel!);
    final room = _room;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      unawaited(room.disconnect().then((_) async => room.dispose()));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return const Scaffold(
        backgroundColor: _dark,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: _gold),
          SizedBox(height: 14),
          Text('Connecting to the live PK battle…', style: TextStyle(color: Colors.white70)),
        ])),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _dark,
        appBar: AppBar(backgroundColor: _dark, title: const Text('BATTLE')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 44),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          ]),
        )),
      );
    }

    return WillPopScope(
      onWillPop: () async { await _leave(); return false; },
      child: Scaffold(
        backgroundColor: NightLinkDesign.background,
        appBar: AppBar(
          backgroundColor: NightLinkDesign.background,
          title: Row(children: [
            const Icon(Icons.circle, color: NightLinkDesign.error, size: 9),
            const SizedBox(width: 7),
            Text(_winner == null ? 'LIVE PK BATTLE' : 'BATTLE RESULT',
              style: const TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w800)),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: (_winner == null ? NightLinkDesign.error : NightLinkDesign.textMuted).withOpacity(.13),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: (_winner == null ? NightLinkDesign.error : NightLinkDesign.textMuted).withOpacity(.24)),
                ),
                child: Text(_winner == null ? _timerText() : 'ENDED',
                  style: TextStyle(color: _winner == null ? NightLinkDesign.error : NightLinkDesign.textMuted,
                      fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ],
        ),
        body: Column(children: [
          if (_winner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF173A2B), Color(0xFF12251F)]),
              ),
              child: Text(
                _winner!['winner_team_no'] == null
                    ? 'DRAW • SCORES TIED'
                    : 'WINNER: TEAM ${_winner!['winner_team_no']}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
            child: LayoutBuilder(builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final team in _teamNumbers)
                    SizedBox(
                      width: cardWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1A2B45), Color(0xFF111827)]),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: NightLinkDesign.blue.withOpacity(.28)),
                        ),
                        child: Row(children: [
                          Container(width: 32, height: 32, alignment: Alignment.center,
                            decoration: BoxDecoration(color: NightLinkDesign.blue.withOpacity(.16),
                                borderRadius: BorderRadius.circular(11)),
                            child: Text('$team', style: const TextStyle(color: NightLinkDesign.blue, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('TEAM $team', style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 10, letterSpacing: .8)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 450),
                                  transitionBuilder: (child, animation) =>
                                      ScaleTransition(scale: animation, child: child),
                                  child: Text(
                                    '${_teamScore(team)}',
                                    key: ValueKey<int>(_teamScore(team)),
                                    style: const TextStyle(color: NightLinkDesign.gold, fontSize: 21, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                if (_scoreDeltas[team] != null) ...[
                                  const SizedBox(width: 7),
                                  Text(
                                    '${_scoreDeltas[team]! > 0 ? '+' : ''}${_scoreDeltas[team]}',
                                    style: TextStyle(
                                      color: _scoreDeltas[team]! > 0 ? Colors.greenAccent : Colors.redAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 5),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: 0,
                                end: (_teamScore(team) / _maxTeamScore).clamp(0.0, 1.0).toDouble(),
                              ),
                              duration: const Duration(milliseconds: 650),
                              curve: Curves.easeOutCubic,
                              builder: (_, value, __) => ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 5,
                                  backgroundColor: Colors.white.withOpacity(.10),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    team == 1 ? NightLinkDesign.blue : Colors.pinkAccent,
                                  ),
                                ),
                              ),
                            ),
                          ])),
                        ]),
                      ),
                    ),
                ],
              );
            }),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: _players.isEmpty
                  ? const Center(child: Text('Waiting for player details…', style: TextStyle(color: Colors.white54)))
                  : GridView.builder(
                      itemCount: _players.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _players.length <= 2 ? 2 : 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: _players.length <= 2 ? .78 : .88,
                      ),
                      itemBuilder: (_, index) => _playerTile(_players[index]),
                    ),
            ),
          ),
          if (_giftBanner != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Container(
                key: ValueKey<String>((_giftBanner!['id'] ?? DateTime.now().microsecondsSinceEpoch).toString()),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF34284B), Color(0xFF241F39)]),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: NightLinkDesign.gold.withOpacity(.55)),
                  boxShadow: [BoxShadow(color: NightLinkDesign.gold.withOpacity(.16), blurRadius: 18, spreadRadius: 1)],
                ),
                child: Row(children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: .35, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.elasticOut,
                    builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                    child: Text((_giftBanner!['gift_emoji'] ?? '🎁').toString(),
                      style: const TextStyle(fontSize: 38)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    '${_giftBanner!['sender_name'] ?? 'Member'} sent ${_giftBanner!['gift_name'] ?? 'a gift'} to ${_giftBanner!['recipient_name'] ?? 'Host'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(color: NightLinkDesign.gold.withOpacity(.15),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('+ ${_giftBanner!['score_added'] ?? 0}',
                        style: const TextStyle(color: NightLinkDesign.gold, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
          SizedBox(
            height: 132,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: _comments.map((comment) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: RichText(text: TextSpan(children: [
                  TextSpan(text: '${comment['display_name']}: ',
                    style: const TextStyle(color: NightLinkDesign.gold, fontWeight: FontWeight.w700)),
                  TextSpan(text: comment['content'].toString(),
                    style: const TextStyle(color: NightLinkDesign.text, height: 1.3)),
                ])),
              )).toList(),
            ),
          ),
          SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: NightLinkDesign.backgroundRaised,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(.07))),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(children: [
                Expanded(child: TextField(
                  controller: _commentController,
                  maxLength: 300,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Write a battle comment…',
                    filled: true,
                    fillColor: NightLinkDesign.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendComment(),
                )),
                IconButton(
                  onPressed: _sendingComment ? null : _sendComment,
                  icon: const Icon(Icons.send_rounded, color: NightLinkDesign.blue),
                ),
                IconButton(
                  onPressed: _showGiftPicker,
                  icon: const Icon(Icons.card_giftcard_rounded, color: NightLinkDesign.gold),
                  tooltip: 'Send a gift',
                ),
                if (_isPlayer) ...[
                  IconButton(
                    onPressed: _toggleMic,
                    tooltip: _micEnabled ? 'Mute microphone' : 'Turn on microphone',
                    icon: Icon(_micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded, color: NightLinkDesign.blue),
                  ),
                  IconButton(
                    onPressed: _toggleCamera,
                    tooltip: _cameraEnabled ? 'Turn camera off' : 'Turn camera on',
                    icon: Icon(_cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded, color: NightLinkDesign.blue),
                  ),
                ],
                IconButton(
                  onPressed: _leave,
                  tooltip: 'Leave battle',
                  icon: const Icon(Icons.call_end_rounded, color: NightLinkDesign.error),
                ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
