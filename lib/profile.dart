import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ads.dart';
import 'nightlink_design.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  bool _loading = true;
  bool _busy = false;
  String _displayName = 'Member';
  String? _avatarUrl;
  String? _error;

  String get _userId => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final row = await _db.from('profiles')
          .select('display_name, avatar_url')
          .eq('id', _userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _displayName = (row?['display_name'] ?? 'Member').toString();
        _avatarUrl = row?['avatar_url']?.toString();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your profile. Please try again.';
      });
    }
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: NightLinkDesign.surface,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: NightLinkDesign.gold),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: NightLinkDesign.blue),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('The selected image is empty.');
      await _uploadPhoto(bytes, file.mimeType ?? 'image/jpeg');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo selection failed: $error')),
        );
      }
    }
  }

  Future<void> _uploadPhoto(Uint8List bytes, String mimeType) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!['image/jpeg', 'image/png', 'image/webp'].contains(mimeType)) {
        mimeType = 'image/jpeg';
      }
      const bucket = 'nightlink-avatars';
      final path = '$_userId/avatar';
      await _db.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: mimeType,
          cacheControl: '3600',
        ),
      );
      final url = '${_db.storage.from(bucket).getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await _db.from('profiles').update({
        'avatar_url': url,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _userId);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your profile photo has been updated.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload your photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_busy || _avatarUrl == null) return;
    setState(() => _busy = true);
    try {
      await _db.storage.from('nightlink-avatars').remove(['$_userId/avatar']);
      await _db.from('profiles').update({
        'avatar_url': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _userId);
      if (!mounted) return;
      setState(() => _avatarUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your profile photo has been removed.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove your photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _db.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('MY PROFILE')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  NightLinkPanel(
                    accent: NightLinkDesign.gold,
                    gradient: true,
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Stack(alignment: Alignment.bottomRight, children: [
                        Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: NightLinkDesign.gold, width: 3),
                          ),
                          child: ClipOval(
                            child: _avatarUrl == null || _avatarUrl!.isEmpty
                                ? NightLinkDesign.avatar(
                                    name: _displayName,
                                    radius: 64,
                                    accent: NightLinkDesign.gold,
                                  )
                                : Image.network(
                                    _avatarUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => NightLinkDesign.avatar(
                                      name: _displayName,
                                      radius: 64,
                                      accent: NightLinkDesign.gold,
                                    ),
                                  ),
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            color: NightLinkDesign.blue,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Change profile photo',
                            onPressed: _busy ? null : _choosePhoto,
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Text(_displayName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text('@${user?.id.substring(0, 8) ?? 'member'}',
                        style: const TextStyle(color: NightLinkDesign.textMuted, fontSize: 12)),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _choosePhoto,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(_avatarUrl == null ? 'ADD PROFILE PHOTO' : 'CHANGE PROFILE PHOTO'),
                        ),
                      ),
                      if (_avatarUrl != null)
                        TextButton.icon(
                          onPressed: _busy ? null : _removePhoto,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove photo'),
                        ),
                      if (_busy) const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: CircularProgressIndicator(),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: NightLinkDesign.error)),
                  NightLinkPanel(
                    accent: NightLinkDesign.blue,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NightLinkDesign.eyebrow('ACCOUNT PRIVACY'),
                      const SizedBox(height: 8),
                      const Text(
                        'Your profile photo and display name can be visible to other NightLink members. Your email address remains private.',
                        style: TextStyle(color: NightLinkDesign.textMuted, height: 1.5),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (nightLinkAdsReady) const NightLinkPrivacyOptionsButton(),
                ],
              ),
            ),
    );
  }
}
