import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'chat.dart';
import 'live_call.dart';
import 'matchmaking.dart';
import 'wallet.dart';

const _gold = Color(0xFFFFC857);
const _blue = Color(0xFF2589FF);
const _dark = Color(0xFF090D18);

class NightLinkFeedScreen extends StatefulWidget {
  const NightLinkFeedScreen({super.key});

  @override
  State<NightLinkFeedScreen> createState() => _NightLinkFeedScreenState();
}

class _NightLinkFeedScreenState extends State<NightLinkFeedScreen> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _musicTracks = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  String get _myId => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final rows = await _db.from('video_posts').select()
          .order('created_at', ascending: false).limit(30);
      final rawPosts = List<Map<String, dynamic>>.from(rows);
      final ids = rawPosts.map((p) => p['user_id'].toString()).toSet().toList();
      final postIds = rawPosts.map((p) => p['id'].toString()).toList();

      final profiles = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _db.from('profiles')
              .select('id, display_name, avatar_url').inFilter('id', ids));
      final interactions = postIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _db.from('video_post_interactions')
              .select('post_id, user_id, action').inFilter('post_id', postIds));
      final comments = postIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _db.from('video_post_comments')
              .select('post_id, id').inFilter('post_id', postIds));
      final tracks = List<Map<String, dynamic>>.from(await _db.from('app_music_tracks')
          .select('id, title, artist, storage_path, duration_seconds')
          .eq('active', true).order('title'));

      final profileMap = {for (final p in profiles) p['id'].toString(): p};
      final enriched = rawPosts.map((post) {
        final postId = post['id'].toString();
        final postInteractions = interactions.where((i) => i['post_id'].toString() == postId);
        final postComments = comments.where((c) => c['post_id'].toString() == postId);
        final profile = profileMap[post['user_id'].toString()];
        final likeRows = postInteractions.where((i) => i['action'] == 'like').toList();
        final shareRows = postInteractions.where((i) => i['action'] == 'share').toList();
        return <String, dynamic>{
          ...post,
          'creator_name': profile?['display_name'] ?? 'NightLink member',
          'creator_avatar': profile?['avatar_url'],
          'like_count': likeRows.length,
          'share_count': shareRows.length,
          'comment_count': postComments.length,
          'liked_by_me': likeRows.any((i) => i['user_id'].toString() == _myId),
          'shared_by_me': shareRows.any((i) => i['user_id'].toString() == _myId),
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _posts = enriched;
        _musicTracks = tracks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the video feed. Check your connection and try again.';
      });
    }
  }

  Future<void> _createPost() async {
    if (_uploading) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF17233A),
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.videocam, color: _gold),
          title: const Text('Record a video (up to 15 seconds)'),
          onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.video_library, color: _blue),
          title: const Text('Choose a video from phone'),
          onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])),
    );
    if (source == null) return;

    final video = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 15),
    );
    if (video == null) return;

    setState(() { _uploading = true; _error = null; });
    try {
      final file = File(video.path);
      final preview = VideoPlayerController.file(file);
      await preview.initialize();
      final duration = preview.value.duration;
      await preview.dispose();
      if (duration.inSeconds < 1 || duration > const Duration(seconds: 15)) {
        throw Exception('Videos must be 15 seconds or shorter.');
      }

      final caption = await _captionDialog();
      if (caption == null) return;
      final music = await _musicDialog();
      if (music == null) return;

      final videoExt = video.path.split('.').last.toLowerCase();
      if (!['mp4', 'mov', 'webm'].contains(videoExt)) {
        throw Exception('Please use an MP4, MOV or WEBM video.');
      }
      final safeVideoExt = videoExt;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final videoPath = '$_myId/$stamp.$safeVideoExt';
      await _db.storage.from('nightlink-videos').upload(
        videoPath, file,
        fileOptions: FileOptions(contentType: _videoMime(safeVideoExt)),
      );

      String? audioPath;
      String audioSource = 'none';
      String? musicTrackId = music['track_id']?.toString();
      if (music['type'] == 'device') {
        final audioFile = music['file'] as File;
        final ext = audioFile.path.split('.').last.toLowerCase();
        if (!['mp3', 'm4a', 'aac', 'wav', 'ogg'].contains(ext)) {
          throw Exception('Please choose an MP3, M4A, AAC, WAV or OGG audio file.');
        }
        final safeExt = ext;
        audioPath = '$_myId/$stamp.$safeExt';
        await _db.storage.from('nightlink-audio').upload(
          audioPath, audioFile,
          fileOptions: FileOptions(contentType: _audioMime(safeExt)),
        );
        audioSource = 'device';
      } else if (music['type'] == 'app') {
        audioPath = music['storage_path']?.toString();
        audioSource = 'app';
      }

      await _db.from('video_posts').insert({
        'user_id': _myId,
        'video_path': videoPath,
        'caption': caption,
        'duration_seconds': duration.inSeconds.clamp(1, 15),
        'audio_source': audioSource,
        'audio_path': audioPath,
        'music_track_id': musicTrackId,
      });
      await _loadFeed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your video is now in the NightLink feed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _videoMime(String ext) => switch (ext) {
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'video/mp4',
  };

  String _audioMime(String ext) => switch (ext) {
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    _ => 'audio/mpeg',
  };

  Future<String?> _captionDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF17233A),
        title: const Text('Add a caption'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Write something about your video…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('NEXT')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _musicDialog() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17233A),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .65,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'ADD MUSIC • Use audio you own or are licensed to use.',
                  style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.volume_off, color: _blue),
                title: const Text('No added music'),
                onTap: () => Navigator.pop(sheetContext, {'type': 'none'}),
              ),
              ListTile(
                leading: const Icon(Icons.library_music, color: _gold),
                title: const Text('Choose audio from my phone'),
                onTap: () async {
                  final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
                  if (picked?.files.single.path == null) return;
                  Navigator.pop(sheetContext, {
                    'type': 'device',
                    'file': File(picked!.files.single.path!),
                  });
                },
              ),
              const Divider(color: Colors.white24),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('NIGHTLINK MUSIC LIBRARY', style: TextStyle(color: _blue, fontWeight: FontWeight.bold)),
              ),
              if (_musicTracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('The app music library is empty for now. Licensed tracks can be added by the developer.',
                    style: TextStyle(color: Colors.white54)),
                ),
              for (final track in _musicTracks)
                ListTile(
                  leading: const Icon(Icons.music_note, color: _gold),
                  title: Text(track['title'].toString()),
                  subtitle: Text((track['artist'] ?? 'NightLink music').toString()),
                  onTap: () => Navigator.pop(sheetContext, {
                    'type': 'app',
                    'track_id': track['id'],
                    'storage_path': track['storage_path'],
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _like(Map<String, dynamic> post) async {
    if (post['liked_by_me'] == true) return;
    try {
      await _db.from('video_post_interactions').insert({
        'post_id': post['id'], 'user_id': _myId, 'action': 'like',
      });
      await _loadFeed();
    } catch (_) {
      await _loadFeed();
    }
  }

  Future<void> _share(Map<String, dynamic> post) async {
    if (post['shared_by_me'] == true) return;
    try {
      final url = _db.storage.from('nightlink-videos').getPublicUrl(post['video_path'].toString());
      final result = await Share.share('Watch this NightLink video: $url');
      if (result.status == ShareResultStatus.success) {
        await _db.from('video_post_interactions').insert({
          'post_id': post['id'], 'user_id': _myId, 'action': 'share',
        });
        await _loadFeed();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This video was already shared by your account.')),
        );
      }
    }
  }

  Future<void> _comments(Map<String, dynamic> post) async {
    final controller = TextEditingController();
    final postId = post['id'].toString();
    List<Map<String, dynamic>> rows = [];
    try {
      rows = List<Map<String, dynamic>>.from(await _db.from('video_post_comments')
          .select('display_name, content, created_at')
          .eq('post_id', postId).order('created_at', ascending: false));
    } catch (_) {}

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17233A),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .55,
            child: Column(children: [
              const Text('COMMENTS', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(child: rows.isEmpty
                  ? const Center(child: Text('Be the first to comment.', style: TextStyle(color: Colors.white54)))
                  : ListView(children: rows.map((row) => ListTile(
                      dense: true,
                      title: Text(row['display_name'].toString(), style: const TextStyle(color: _gold)),
                      subtitle: Text(row['content'].toString()),
                    )).toList())),
              Row(children: [
                Expanded(child: TextField(
                  controller: controller,
                  maxLength: 500,
                  decoration: const InputDecoration(counterText: '', hintText: 'Write one comment…'),
                )),
                IconButton(
                  icon: const Icon(Icons.send, color: _blue),
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    try {
                      final profile = await _db.from('profiles').select('display_name').eq('id', _myId).maybeSingle();
                      await _db.from('video_post_comments').insert({
                        'post_id': postId,
                        'user_id': _myId,
                        'display_name': profile?['display_name'] ?? 'Member',
                        'content': text,
                      });
                      controller.clear();
                      rows = List<Map<String, dynamic>>.from(await _db.from('video_post_comments')
                          .select('display_name, content, created_at')
                          .eq('post_id', postId).order('created_at', ascending: false));
                      setSheetState(() {});
                      await _loadFeed();
                    } catch (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You can add one comment per video.')),
                      );
                    }
                  },
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  void _openConnections() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17233A),
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.chat, color: _gold), title: const Text('Text chat'),
          onTap: () { Navigator.pop(context); Navigator.push(this.context, MaterialPageRoute(builder: (_) => const ChatScreen())); }),
        ListTile(leading: const Icon(Icons.mic, color: _blue), title: const Text('Voice chat'),
          onTap: () { Navigator.pop(context); Navigator.push(this.context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.voice))); }),
        ListTile(leading: const Icon(Icons.videocam, color: _gold), title: const Text('Video chat'),
          onTap: () { Navigator.pop(context); Navigator.push(this.context, MaterialPageRoute(builder: (_) => const CallContactsScreen(mode: NightLinkCallMode.video))); }),
        ListTile(leading: const Icon(Icons.sports_esports, color: _blue), title: const Text('Find a match / watch battles'),
          onTap: () { Navigator.pop(context); Navigator.push(this.context, MaterialPageRoute(builder: (_) => const MatchLobby())); }),
        ListTile(leading: const Icon(Icons.monetization_on, color: _gold), title: const Text('Coins and gifts'),
          onTap: () { Navigator.pop(context); Navigator.push(this.context, MaterialPageRoute(builder: (_) => const CoinWalletScreen())); }),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(
      backgroundColor: _dark,
      title: const Text('NIGHTLINK', style: TextStyle(color: _gold, fontWeight: FontWeight.bold, letterSpacing: 2)),
      actions: [
        IconButton(onPressed: _openConnections, icon: const Icon(Icons.grid_view, color: _blue), tooltip: 'Chat, calls, matches and wallet'),
        IconButton(onPressed: () async => _db.auth.signOut(), icon: const Icon(Icons.logout, color: Colors.white70)),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _uploading ? null : _createPost,
      backgroundColor: _gold,
      foregroundColor: _dark,
      icon: _uploading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.add_a_photo),
      label: Text(_uploading ? 'UPLOADING…' : 'POST 15s VIDEO'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: _gold))
        : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, style: const TextStyle(color: Colors.white70)),
                ElevatedButton(onPressed: _loadFeed, child: const Text('RETRY')),
              ]))
            : RefreshIndicator(
                onRefresh: _loadFeed,
                color: _gold,
                child: _posts.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 140),
                        Icon(Icons.video_library_outlined, color: _blue, size: 60),
                        SizedBox(height: 18),
                        Center(child: Text('Your NightLink video feed starts here.',
                          style: TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.bold))),
                        SizedBox(height: 8),
                        Center(child: Text('Post your first 15-second video.', style: TextStyle(color: Colors.white60))),
                        SizedBox(height: 160),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final post = _posts[index];
                          final videoUrl = _db.storage.from('nightlink-videos')
                              .getPublicUrl(post['video_path'].toString());
                          String? audioUrl;
                          if (post['audio_path'] != null && post['audio_path'].toString().isNotEmpty) {
                            final bucket = post['audio_source'] == 'app' ? 'nightlink-audio' : 'nightlink-audio';
                            audioUrl = _db.storage.from(bucket).getPublicUrl(post['audio_path'].toString());
                          }
                          return _VideoPostCard(
                            key: ValueKey(post['id']),
                            post: post,
                            videoUrl: videoUrl,
                            audioUrl: audioUrl,
                            onLike: () => _like(post),
                            onComment: () => _comments(post),
                            onShare: () => _share(post),
                          );
                        },
                      ),
              ),
  );
}

class _VideoPostCard extends StatefulWidget {
  const _VideoPostCard({
    super.key,
    required this.post,
    required this.videoUrl,
    required this.audioUrl,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  final Map<String, dynamic> post;
  final String videoUrl;
  final String? audioUrl;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  State<_VideoPostCard> createState() => _VideoPostCardState();
}

class _VideoPostCardState extends State<_VideoPostCard> {
  late final VideoPlayerController _video;
  final AudioPlayer _audio = AudioPlayer();
  bool _ready = false;
  bool _audioReady = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _video.initialize();
      await _video.setLooping(true);
      if (widget.audioUrl != null) {
        await _video.setVolume(0);
        await _audio.setUrl(widget.audioUrl!);
        _audioReady = true;
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  Future<void> _togglePlay() async {
    if (!_ready) return;
    if (_playing) {
      await _video.pause();
      if (_audioReady) await _audio.pause();
    } else {
      await _video.play();
      if (_audioReady) {
        await _audio.seek(Duration.zero);
        await _audio.play();
      }
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  void dispose() {
    _video.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF11182B),
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0x332589FF),
          backgroundImage: widget.post['creator_avatar'] == null
              ? null : NetworkImage(widget.post['creator_avatar'].toString()),
          child: widget.post['creator_avatar'] == null ? const Icon(Icons.person, color: _blue) : null,
        ),
        title: Text(widget.post['creator_name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${widget.post['duration_seconds']} sec • NightLink feed',
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ),
      GestureDetector(
        onTap: _togglePlay,
        child: AspectRatio(
          aspectRatio: _ready && _video.value.aspectRatio > 0 ? _video.value.aspectRatio : 9 / 16,
          child: Stack(fit: StackFit.expand, children: [
            if (_ready) VideoPlayer(_video)
            else const ColoredBox(color: Color(0xFF17233A),
              child: Center(child: CircularProgressIndicator(color: _gold))),
            if (!_playing)
              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 64)),
          ]),
        ),
      ),
      if ((widget.post['caption'] ?? '').toString().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Text(widget.post['caption'].toString(), style: const TextStyle(color: Colors.white)),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          TextButton.icon(
            onPressed: widget.onLike,
            icon: Icon(widget.post['liked_by_me'] == true ? Icons.favorite : Icons.favorite_border,
              color: widget.post['liked_by_me'] == true ? Colors.redAccent : _gold),
            label: Text('${widget.post['like_count']}', style: const TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            onPressed: widget.onComment,
            icon: const Icon(Icons.mode_comment_outlined, color: _blue),
            label: Text('${widget.post['comment_count']}', style: const TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            onPressed: widget.onShare,
            icon: Icon(Icons.share_outlined,
              color: widget.post['shared_by_me'] == true ? _gold : _blue),
            label: Text('${widget.post['share_count']}', style: const TextStyle(color: Colors.white70)),
          ),
          const Spacer(),
          if (widget.post['audio_source'] != 'none')
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.music_note, color: _gold, size: 18),
            ),
        ]),
      ),
    ]),
  );
}
