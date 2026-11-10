import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connections.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

final GlobalKey<NavigatorState> nightLinkNavigatorKey = GlobalKey<NavigatorState>();

enum NightLinkCallMode { voice, video }

class CallContactsScreen extends StatefulWidget {
  const CallContactsScreen({super.key, required this.mode});
  final NightLinkCallMode mode;

  @override
  State<CallContactsScreen> createState() => _CallContactsScreenState();
}

class _CallContactsScreenState extends State<CallContactsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;
    try {
      final links = await _client.from('friendships')
          .select('user_low_id, user_high_id')
          .or('user_low_id.eq.${currentUser.id},user_high_id.eq.${currentUser.id}');
      final ids = (links as List).map((row) {
        final low = row['user_low_id'].toString();
        final high = row['user_high_id'].toString();
        return low == currentUser.id ? high : low;
      }).toList();
      final rows = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client.from('profiles')
              .select('id, username, display_name')
              .inFilter('id', ids).order('display_name');
      if (!mounted) return;
      setState(() {
        _people = List<Map<String, dynamic>>.from(rows);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load members. Please try again.';
      });
    }
  }

  String _roomName(String otherId) {
    final ids = [ _client.auth.currentUser!.id, otherId ]..sort();
    // UUID prefixes keep the room name within LiveKit's 64-character limit.
    final first = ids[0].replaceAll('-', '').substring(0, 24);
    final second = ids[1].replaceAll('-', '').substring(0, 24);
    final prefix = widget.mode == NightLinkCallMode.voice ? 'voice' : 'video';
    return '${prefix}_${first}_${second}';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.mode == NightLinkCallMode.video;
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        title: Text(isVideo ? 'VIDEO CHAT' : 'VOICE CHAT',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Find members',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
              _loadPeople();
            },
            icon: const Icon(Icons.person_search, color: _gold),
          ),
          IconButton(
            onPressed: _loadPeople,
            icon: const Icon(Icons.refresh, color: _blue),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: const TextStyle(color: Colors.white70)),
                    ElevatedButton(onPressed: _loadPeople, child: const Text('RETRY')),
                  ]),
                )
              : _people.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(26),
                        child: Text(
                          'No accepted connections yet. Use the people-search icon above to find a member and send a connection request.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, height: 1.5),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Choose a member to join a private live room.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap CALL to send an invitation. The other member will see Accept or Decline inside NightLink.',
                          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        for (final person in _people)
                          Card(
                            color: const Color(0xFF11182B),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0x332589FF),
                                child: Icon(isVideo ? Icons.videocam : Icons.mic, color: _blue),
                              ),
                              title: Text(
                                (person['display_name'] ?? person['username'] ?? 'NightLink member').toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: const Text('Send a live call invitation', style: TextStyle(color: Colors.white54)),
                              trailing: const Icon(Icons.call, size: 22, color: _gold),
                              onTap: () async {
                                final name = (person['display_name'] ?? person['username'] ?? 'Member').toString();
                                try {
                                  final invitation = await _client.from('call_invitations').insert({
                                    'caller_id': _client.auth.currentUser!.id,
                                    'receiver_id': person['id'].toString(),
                                    'call_mode': widget.mode == NightLinkCallMode.voice ? 'voice' : 'video',
                                    'room_name': _roomName(person['id'].toString()),
                                  }).select('id').single();
                                  if (!mounted) return;
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => OutgoingCallScreen(
                                      invitationId: invitation['id'].toString(),
                                      mode: widget.mode,
                                      otherName: name,
                                    ),
                                  ));
                                } catch (error) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Could not send invitation: $error')),
                                  );
                                }
                              },
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  final _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;
  String? _subscribedUserId;
  Timer? _pendingPoll;
  Map<String, dynamic>? _invite;
  String _callerName = 'NightLink member';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _configureForCurrentUser();
    });
    _configureForCurrentUser();
  }

  void _configureForCurrentUser() {
    final userId = _client.auth.currentUser?.id;
    if (userId == _subscribedUserId) return;
    final previous = _channel;
    _channel = null;
    _pendingPoll?.cancel();
    _pendingPoll = null;
    _subscribedUserId = userId;
    if (previous != null) _client.removeChannel(previous);
    if (userId == null) {
      if (mounted) setState(() => _invite = null);
      return;
    }
    _loadPending();
    // Keep incoming call alerts working when a device suspends Realtime.
    _pendingPoll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadPending();
    });
    _channel = _client
        .channel('global-incoming-calls-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (_) => _loadPending(),
        )
        .subscribe();
  }

  Future<void> _loadPending() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await _client
          .from('call_invitations')
          .select('id, caller_id, call_mode, room_name, expires_at')
          .eq('receiver_id', userId)
          .eq('status', 'pending')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at')
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _invite = null);
        return;
      }
      var name = 'NightLink member';
      try {
        final profile = await _client
            .from('profiles')
            .select('display_name, username')
            .eq('id', row['caller_id'])
            .maybeSingle();
        name = (profile?['display_name'] ?? profile?['username'] ?? name).toString();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _invite = Map<String, dynamic>.from(row);
        _callerName = name;
      });
    } catch (_) {}
  }

  Future<void> _respond(bool accept) async {
    final invite = _invite;
    if (invite == null || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await _client
          .from('call_invitations')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', invite['id'])
          .eq('status', 'pending')
          .select('id, status')
          .maybeSingle();
      if (updated == null || updated['status'] != (accept ? 'accepted' : 'declined')) {
        throw Exception('This invitation is no longer available. Ask the caller to try again.');
      }
      if (!mounted) return;
      setState(() => _invite = null);
      if (accept) {
        final mode = invite['call_mode'] == 'video'
            ? NightLinkCallMode.video
            : NightLinkCallMode.voice;
        await nightLinkNavigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => LiveCallScreen(
            invitationId: invite['id'].toString(),
            mode: mode,
            otherName: _callerName,
          ),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not respond to call: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _client.removeChannel(channel);
    _pendingPoll?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_invite != null)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 12,
          right: 12,
          child: Material(
            color: const Color(0xFF182642),
            elevation: 18,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_invite!['call_mode'] == 'video' ? Icons.videocam : Icons.call,
                        color: _gold, size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _invite!['call_mode'] == 'video' ? 'INCOMING VIDEO CALL' : 'INCOMING VOICE CALL',
                      style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Text('$_callerName is calling you.',
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _respond(false),
                      icon: const Icon(Icons.call_end),
                      label: const Text('DECLINE'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _respond(true),
                      icon: const Icon(Icons.call),
                      label: const Text('ACCEPT'),
                      style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: _dark),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
    super.key,
    required this.invitationId,
    required this.mode,
    required this.otherName,
  });

  final String invitationId;
  final NightLinkCallMode mode;
  final String otherName;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  final _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _statusPoll;
  bool _checkingStatus = false;
  String _status = 'Calling... waiting for the member to accept';
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _watchInvitation();
  }

  void _watchInvitation() {
    _channel = _client
        .channel('outgoing-call-${widget.invitationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.invitationId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status']?.toString();
            if (status == 'accepted' && !_opening) {
              _opening = true;
              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (_) => LiveCallScreen(
                    invitationId: widget.invitationId,
                    mode: widget.mode,
                    otherName: widget.otherName,
                  ),
                ));
              }
            } else if (status == 'declined' && mounted) {
              setState(() => _status = '${widget.otherName} declined the call.');
            } else if (status == 'cancelled' && mounted) {
              setState(() => _status = 'Call invitation was cancelled.');
            }
          },
        )
        .subscribe();
    _checkCurrentStatus();
    // Realtime can be delayed when Android suspends the app or changes networks.
    _statusPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_opening) _checkCurrentStatus();
    });
  }

  Future<void> _checkCurrentStatus() async {
    if (_checkingStatus || _opening) return;
    _checkingStatus = true;
    try {
      final row = await _client
          .from('call_invitations')
          .select('status, expires_at')
          .eq('id', widget.invitationId)
          .maybeSingle();
      final status = row?['status']?.toString();
      if (status == 'accepted' && !_opening && mounted) {
        _opening = true;
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => LiveCallScreen(
            invitationId: widget.invitationId,
            mode: widget.mode,
            otherName: widget.otherName,
          ),
        ));
      } else if (status == 'declined' && mounted) {
        _statusPoll?.cancel();
        setState(() => _status = '${widget.otherName} declined the call.');
      } else if (status == 'cancelled' && mounted) {
        _statusPoll?.cancel();
        setState(() => _status = 'The invitation was cancelled.');
      } else if (row?['expires_at'] != null &&
          DateTime.tryParse(row!['expires_at'].toString())?.isBefore(DateTime.now().toUtc()) == true &&
          mounted) {
        _statusPoll?.cancel();
        setState(() => _status = 'The invitation expired. Please call again.');
      }
    } catch (error) {
      debugPrint('NightLink outgoing call status check failed: $error');
    } finally {
      _checkingStatus = false;
    }
  }

  Future<void> _cancel() async {
    try {
      await _client.from('call_invitations')
          .update({'status': 'cancelled'})
          .eq('id', widget.invitationId)
          .eq('status', 'pending');
    } catch (_) {}
    _statusPoll?.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    final channel = _channel;
    if (channel != null) {
      _client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(
      backgroundColor: _dark,
      title: Text(widget.mode == NightLinkCallMode.video ? 'VIDEO INVITATION' : 'VOICE INVITATION'),
      leading: IconButton(onPressed: _cancel, icon: const Icon(Icons.close)),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.mode == NightLinkCallMode.video ? Icons.videocam : Icons.call,
                color: _gold, size: 68),
            const SizedBox(height: 20),
            Text('Calling ${widget.otherName}',
                style: const TextStyle(color: _gold, fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.call_end),
              label: const Text('CANCEL INVITATION'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            ),
          ],
        ),
      ),
    ),
  );
}

class LiveCallScreen extends StatefulWidget {
  const LiveCallScreen({
    super.key,
    required this.invitationId,
    required this.mode,
    required this.otherName,
  });

  final String invitationId;
  final NightLinkCallMode mode;
  final String otherName;

  @override
  State<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends State<LiveCallScreen> {
  Room? _room;
  bool _connecting = true;
  bool _connected = false;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  String? _error;

  bool get _isVideo => widget.mode == NightLinkCallMode.video;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    Room? connectingRoom;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'generate-livekit-token',
        body: {'invitationId': widget.invitationId},
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        final detail = data is Map ? data['error']?.toString() : null;
        throw Exception(detail ?? 'Could not get a secure call token (HTTP ${response.status}).');
      }

      final token = data['token']?.toString();
      final serverUrl = data['serverUrl']?.toString();
      if (token == null || token.isEmpty || serverUrl == null || serverUrl.isEmpty) {
        throw Exception('The call server returned incomplete connection details.');
      }

      final room = Room();
      connectingRoom = room;
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
      ).timeout(const Duration(seconds: 35));

      // Audio routing differs across Android vendors. A routing API failure
      // must not tear down an otherwise valid LiveKit room.
      try {
        await AudioManager.instance.setSpeakerOutputPreferred(_isVideo);
      } catch (routeError) {
        debugPrint('NightLink audio route preference unavailable: $routeError');
      }
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (_isVideo) {
        await room.localParticipant?.setCameraEnabled(true);
      }

      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = true;
        _micEnabled = true;
        _cameraEnabled = _isVideo;
      });
    } catch (error) {
      debugPrint('NightLink private call connection failed: $error');
      final room = connectingRoom;
      if (room != null) {
        room.removeListener(_onRoomChanged);
        try { await room.disconnect(); } catch (_) {}
        try { await room.dispose(); } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _room = null;
        _connecting = false;
        _connected = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null) return;
    final next = !_micEnabled;
    try {
      await room.localParticipant?.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micEnabled = next);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleCamera() async {
    final room = _room;
    if (room == null || !_isVideo) return;
    final next = !_cameraEnabled;
    try {
      await room.localParticipant?.setCameraEnabled(next);
      if (mounted) setState(() => _cameraEnabled = next);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Call control failed: $error')),
    );
  }

  Future<void> _leave() async {
    final room = _room;
    _room = null;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      await room.disconnect();
      await room.dispose();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    final room = _room;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      unawaited(room.disconnect().then((_) async { await room.dispose(); }));
    }
    super.dispose();
  }

  Widget _videoTile(dynamic participant, String label) {
    final publications = participant.videoTrackPublications;
    for (final publication in publications) {
      final track = publication.track;
      if (track != null && !publication.muted) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: VideoTrackRenderer(track as VideoTrack),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF17233A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person, color: _blue, size: 54),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70)),
            const Text('Camera off', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final remoteCount = room?.remoteParticipants.length ?? 0;
    final local = room?.localParticipant;

    return WillPopScope(
      onWillPop: () async {
        await _leave();
        return false;
      },
      child: Scaffold(
        backgroundColor: _dark,
        appBar: AppBar(
          backgroundColor: _dark,
          title: Text(_isVideo ? 'VIDEO CALL' : 'VOICE CALL'),
          leading: IconButton(onPressed: _leave, icon: const Icon(Icons.close)),
        ),
        body: _connecting
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: _gold),
                    SizedBox(height: 18),
                    Text('Connecting securely to LiveKit...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 48),
                          const SizedBox(height: 14),
                          const Text('Could not start the call', style: TextStyle(color: _gold, fontSize: 18)),
                          const SizedBox(height: 10),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 18),
                          ElevatedButton(onPressed: _leave, child: const Text('CLOSE')),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _isVideo
                            ? ListView(
                                padding: const EdgeInsets.all(12),
                                children: [
                                  if (local != null)
                                    SizedBox(
                                      height: 260,
                                      child: _videoTile(local, 'You'),
                                    ),
                                  for (final participant in room!.remoteParticipants.values)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: SizedBox(
                                        height: 260,
                                        child: _videoTile(participant, widget.otherName),
                                      ),
                                    ),
                                  if (remoteCount == 0)
                                    const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: Text(
                                        'You are in the room. Waiting for the other member to join...',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                ],
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircleAvatar(
                                      radius: 48,
                                      backgroundColor: Color(0x332589FF),
                                      child: Icon(Icons.headset_mic, color: _blue, size: 44),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(widget.otherName, style: const TextStyle(color: _gold, fontSize: 22)),
                                    const SizedBox(height: 8),
                                    Text(
                                      remoteCount > 0 ? 'Member connected' : 'Waiting for the other member to join...',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _CallControl(
                                icon: _micEnabled ? Icons.mic : Icons.mic_off,
                                label: _micEnabled ? 'Mute' : 'Unmute',
                                onTap: _toggleMic,
                              ),
                              if (_isVideo) ...[
                                const SizedBox(width: 24),
                                _CallControl(
                                  icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                                  label: _cameraEnabled ? 'Camera off' : 'Camera on',
                                  onTap: _toggleCamera,
                                ),
                              ],
                              const SizedBox(width: 24),
                              _CallControl(
                                icon: Icons.call_end,
                                label: 'End',
                                color: Colors.redAccent,
                                onTap: _leave,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = _blue,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withOpacity(.18),
            child: IconButton(
              onPressed: onTap,
              icon: Icon(icon, color: color),
              iconSize: 25,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );
}
