import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';

/// Create a story: text, photo or video (24h expiry, like Telegram).
class StoryCreateScreen extends ConsumerStatefulWidget {
  const StoryCreateScreen({super.key});
  @override
  ConsumerState<StoryCreateScreen> createState() => _StoryCreateScreenState();
}

class _StoryCreateScreenState extends ConsumerState<StoryCreateScreen> {
  final _textCtrl = TextEditingController();
  File? _file;
  bool _isVideo = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60))
        : await picker.pickImage(source: source, maxWidth: 1920, imageQuality: 88);
    if (picked == null || !mounted) return;
    setState(() {
      _file = File(picked.path);
      _isVideo = video;
    });
  }

  Future<void> _publish() async {
    if (_sending) return;
    final text = _textCtrl.text.trim();
    if (_file == null && text.isEmpty) {
      setState(() => _error = 'متن یا عکس/ویدیو برای استوری لازم است');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final api = ref.read(authenticatedSessionProvider).api;
      String? mediaId;
      String storyType = 'text';
      if (_file != null) {
        final upload = await api.uploadFile('/media/upload', _file!);
        mediaId = upload['id'] as String?;
        storyType = _isVideo ? 'video' : 'image';
      }
      await api.post('/stories/', {
        'story_type': storyType,
        'content': text.isEmpty ? null : text,
        'media_id': mediaId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استوری جدید')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _textCtrl,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'متن استوری (اختیاری با عکس/ویدیو)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_file != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _isVideo
                        ? Container(
                            height: 220,
                            color: Colors.black12,
                            child: const Center(child: Icon(Icons.videocam, size: 48, color: Colors.grey)),
                          )
                        : Image.file(_file!, height: 260, width: double.infinity, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _file = null),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.gallery, video: false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('عکس از گالری'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera, video: false),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('دوربین'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.gallery, video: true),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('ویدیو'),
                  ),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sending ? null : _publish,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'در حال انتشار...' : 'انتشار استوری (۲۴ ساعته)'),
            ),
          ],
        ),
      ),
    );
  }
}
