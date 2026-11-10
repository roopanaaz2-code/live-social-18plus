import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connections.dart';
import 'nightlink_design.dart';

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
      backgroundColor: NightLinkDesign.background,
      appBar: AppBar(
        backgroundColor: NightLinkDesign.background,
        title: Text(isVideo ? 'Video calls' : 'Voice calls'),
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
            onPressed: _loadPeople,
            tooltip: 'Refresh contacts',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NightLinkDesign.gold))
          : _error != null
              ? Center(
                  child: NightLinkPanel(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.wifi_off_rounded, color: NightLinkDesign.error, size: 36),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center,
                          style: const TextStyle(color: NightLinkDesign.textMuted)),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(onPressed: _loadPeople,
                          icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                    ]),
                  ),
                )
              : _people.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(26),
                        child: NightLinkPanel(
                          accent: NightLinkDesign.gold,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.people_alt_outlined, size: 42, color: NightLinkDesign.gold),
                            const SizedBox(height: 14),
                            const Text('Your circle starts here',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(
                              'No accepted connections yet. Use people search to find a member and send a connection request.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: NightLinkDesign.textMuted, height: 1.5),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
                                _loadPeople();
                              },
                              icon: const Icon(Icons.person_search_rounded),
                              label: const Text('Find people'),
                            ),
                          ]),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                      children: [
                        NightLinkPanel(
                          accent: isVideo ? NightLinkDesign.blue : NightLinkDesign.gold,
                          gradient: true,
                          padding: const EdgeInsets.all(20),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            NightLinkDesign.eyebrow(isVideo ? 'Face to face' : 'Stay connected',
                                color: isVideo ? NightLinkDesign.blue : NightLinkDesign.gold),
                            const SizedBox(height: 9),
                            Text(isVideo ? 'Make it a video moment' : 'Start with a voice call',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 7),
                            const Text('Choose a connection to send a private call invitation.',
                                style: TextStyle(color: NightLinkDesign.textMuted, height: 1.4)),
                          ]),
                        ),
                        const SizedBox(height: 22),
                        Row(children: [
                          const Expanded(child: Text('YOUR CONNECTIONS',
                              style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 11,
                                  fontWeight: FontWeight.w700, letterSpacing: 1.2))),
                          Text('${_people.length} members',
                              style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 10),
                        for (final person in _people)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(NightLinkDesign.radius),
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
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                                  decoration: NightLinkDesign.surfaceDecoration(accent: isVideo
                                      ? NightLinkDesign.blue : NightLinkDesign.gold, radius: 20),
                                  child: Row(children: [
                                    NightLinkDesign.avatar(
                                      name: (person['display_name'] ?? person['username'] ?? 'NightLink member').toString(),
                                      radius: 25,
                                      accent: isVideo ? NightLinkDesign.blue : NightLinkDesign.gold,
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text((person['display_name'] ?? person['username'] ?? 'NightLink member').toString(),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      const Text('Available to connect',
                                          style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
                                    ])),
                                    const SizedBox(width: 10),
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: (isVideo ? NightLinkDesign.blue : NightLinkDesign.gold).withOpacity(.16),
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                                          color: isVideo ? NightLinkDesign.blue : NightLinkDesign.gold),
                                    ),
                                  ]),
                                ),
                              ),
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
    _subscribedUserId = userId;
    if (previous != null) _client.removeChannel(previous);
    if (userId == null) {
      if (mounted) setState(() => _invite = null);
      return;
    }
    _loadPending();
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
      await _client
          .from('call_invitations')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', invite['id'])
          .eq('status', 'pending');
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
            color: Colors.transparent,
            elevation: 12,
            borderRadius: BorderRadius.circular(NightLinkDesign.radius),
            child: NightLinkPanel(
              accent: NightLinkDesign.gold,
              gradient: true,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: _gold.withOpacity(.15), borderRadius: BorderRadius.circular(14)),
                      child: Icon(_invite!['call_mode'] == 'video' ? Icons.videocam_rounded : Icons.call_rounded,
                          color: _gold, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _invite!['call_mode'] == 'video' ? 'INCOMING VIDEO CALL' : 'INCOMING VOICE CALL',
                      style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, letterSpacing: .8),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    NightLinkDesign.avatar(name: _callerName, radius: 23, accent: NightLinkDesign.gold),
                    const SizedBox(width: 12),
                    Expanded(child: Text('$_callerName is calling you.',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _respond(false),
                      icon: const Icon(Icons.call_end),
                      label: const Text('DECLINE'),
                      style: ElevatedButton.styleFrom(backgroundColor: NightLinkDesign.error, foregroundColor: Colors.white),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _respond(true),
                      icon: const Icon(Icons.call),
                      label: const Text('ACCEPT'),
                      style: ElevatedButton.styleFrom(backgroundColor: NightLinkDesign.success, foregroundColor: Colors.white),
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
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final row = await _client
          .from('call_invitations')
          .select('status')
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
        setState(() => _status = '${widget.otherName} declined the call.');
      }
    } catch (_) {}
  }

  Future<void> _cancel() async {
    try {
      await _client.from('call_invitations')
          .update({'status': 'cancelled'})
          .eq('id', widget.invitationId)
          .eq('status', 'pending');
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      _client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: NightLinkDesign.background,
    appBar: AppBar(
      backgroundColor: NightLinkDesign.background,
      title: Text(widget.mode == NightLinkCallMode.video ? 'Video invitation' : 'Voice invitation'),
      leading: IconButton(onPressed: _cancel, icon: const Icon(Icons.close_rounded)),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: NightLinkPanel(
          accent: NightLinkDesign.gold,
          gradient: true,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            NightLinkDesign.avatar(name: widget.otherName, radius: 52, accent: NightLinkDesign.gold),
            const SizedBox(height: 20),
            NightLinkDesign.eyebrow('Private ${widget.mode == NightLinkCallMode.video ? 'video' : 'voice'} room', color: NightLinkDesign.gold),
            const SizedBox(height: 8),
            Text('Calling ${widget.otherName}', textAlign: TextAlign.center,
                style: const TextStyle(color: NightLinkDesign.text, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(_status, textAlign: TextAlign.center,
                style: const TextStyle(color: NightLinkDesign.textMuted, height: 1.45)),
            const SizedBox(height: 26),
            const CircularProgressIndicator(color: NightLinkDesign.gold, strokeWidth: 2.5),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.call_end_rounded),
              label: const Text('Cancel invitation'),
              style: ElevatedButton.styleFrom(backgroundColor: NightLinkDesign.error, foregroundColor: Colors.white),
            )),
          ]),
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

      // Voice calls use the earpiece by default to reduce speaker-to-microphone echo.
      // Video calls use the speaker so both participants are easier to hear.
      await AudioManager.instance.setSpeakerOutputPreferred(_isVideo);
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
      if (!mounted) return;
      setState(() {
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
        gradient: const LinearGradient(colors: [Color(0xFF1B2D49), Color(0xFF101725)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NightLinkDesign.avatar(name: label, radius: 36, accent: NightLinkDesign.blue),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: NightLinkDesign.text, fontWeight: FontWeight.w600)),
            const Text('Camera off', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
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
        backgroundColor: NightLinkDesign.background,
        appBar: AppBar(
          backgroundColor: NightLinkDesign.background,
          title: Text(_isVideo ? 'Video call' : 'Voice call'),
          leading: IconButton(onPressed: _leave, icon: const Icon(Icons.close_rounded)),
        ),
        body: _connecting
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: NightLinkDesign.gold),
                  SizedBox(height: 18),
                  Text('Connecting securely to LiveKit...', style: TextStyle(color: NightLinkDesign.textMuted)),
                ]),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: NightLinkPanel(
                        accent: NightLinkDesign.error,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded, color: NightLinkDesign.error, size: 48),
                          const SizedBox(height: 14),
                          const Text('Could not start the call', style: TextStyle(color: NightLinkDesign.gold, fontSize: 18)),
                          const SizedBox(height: 10),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: NightLinkDesign.textMuted)),
                          const SizedBox(height: 18),
                          ElevatedButton(onPressed: _leave, child: const Text('Close')),
                        ]),
                      ),
                    ),
                  )
                : Column(children: [
                    Expanded(
                      child: _isVideo
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Stack(fit: StackFit.expand, children: [
                                  if (remoteCount > 0)
                                    _videoTile(room!.remoteParticipants.values.first, widget.otherName)
                                  else if (local != null)
                                    _videoTile(local, 'You')
                                  else
                                    Container(color: NightLinkDesign.surface),
                                  Positioned(
                                    top: 14, left: 14,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                      decoration: BoxDecoration(color: Colors.black.withOpacity(.64),
                                          borderRadius: BorderRadius.circular(30)),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.circle, size: 8,
                                            color: remoteCount > 0 ? NightLinkDesign.success : NightLinkDesign.gold),
                                        const SizedBox(width: 7),
                                        Text(remoteCount > 0 ? widget.otherName : 'Waiting for ${widget.otherName}',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  ),
                                  if (local != null && remoteCount > 0)
                                    Positioned(
                                      right: 14, bottom: 14, width: 112, height: 154,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(border: Border.all(color: Colors.white24, width: 1.2)),
                                          child: _videoTile(local, 'You'),
                                        ),
                                      ),
                                    ),
                                  if (remoteCount == 0)
                                    Positioned(left: 18, right: 18, bottom: 22,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: Colors.black.withOpacity(.58),
                                            borderRadius: BorderRadius.circular(16)),
                                        child: const Text('You’re in the room. Your connection will appear here when they join.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35)),
                                      ),
                                    ),
                                ]),
                              ),
                            )
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: NightLinkPanel(
                                  accent: NightLinkDesign.blue,
                                  gradient: true,
                                  padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 38),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    NightLinkDesign.avatar(name: widget.otherName, radius: 58, accent: NightLinkDesign.blue),
                                    const SizedBox(height: 20),
                                    Text(widget.otherName, textAlign: TextAlign.center,
                                        style: const TextStyle(color: NightLinkDesign.text, fontSize: 23, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 9),
                                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Icon(Icons.circle, size: 8,
                                          color: remoteCount > 0 ? NightLinkDesign.success : NightLinkDesign.gold),
                                      const SizedBox(width: 7),
                                      Text(remoteCount > 0 ? 'Connected' : 'Waiting for them to join',
                                          style: const TextStyle(color: NightLinkDesign.textMuted)),
                                    ]),
                                    const SizedBox(height: 18),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(.05),
                                          borderRadius: BorderRadius.circular(30)),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.lock_outline_rounded, size: 15, color: NightLinkDesign.textMuted),
                                        SizedBox(width: 7),
                                        Text('Private voice room', style: TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
                                      ]),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _CallControl(
                            icon: _micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                            label: _micEnabled ? 'Mute' : 'Unmute',
                            onTap: _toggleMic,
                          ),
                          if (_isVideo) ...[
                            const SizedBox(width: 28),
                            _CallControl(
                              icon: _cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                              label: _cameraEnabled ? 'Camera off' : 'Camera on',
                              onTap: _toggleCamera,
                            ),
                          ],
                          const SizedBox(width: 28),
                          _CallControl(
                            icon: Icons.call_end_rounded,
                            label: 'End call',
                            color: NightLinkDesign.error,
                            onTap: _leave,
                          ),
                        ]),
                      ),
                    ),
                  ]),
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
          Material(
            color: color == NightLinkDesign.error ? color : color.withOpacity(.16),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(width: 58, height: 58,
                child: Icon(icon, color: color == NightLinkDesign.error ? Colors.white : color, size: 25)),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      );
}
