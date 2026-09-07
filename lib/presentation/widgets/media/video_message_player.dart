import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String url;
  final String? authToken;
  final bool isMine;

  const VideoMessagePlayer({
    super.key,
    required this.url,
    this.authToken,
    this.isMine = false,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final headers = <String, String>{};
      if (widget.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.authToken}';
      }
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: headers,
      );
      await _controller!.initialize();
      _chewie = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: false,
        looping: false,
        aspectRatio: _controller!.value.aspectRatio,
        errorBuilder: (_, __) => const Center(child: Icon(Icons.error)),
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        width: 220,
        height: 140,
        color: Colors.black26,
        child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
      );
    }
    if (_chewie == null) {
      return Container(
        width: 220,
        height: 140,
        color: Colors.black26,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 240,
        height: 160,
        child: Chewie(controller: _chewie!),
      ),
    );
  }
}
