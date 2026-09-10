import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Result of editing a video: the original file plus edit instructions.
/// Trimming is applied server-side (ffmpeg) at upload; [muted] is enforced
/// at playback by every client, so a muted video stays silent everywhere.
class EditedVideo {
  final File file;
  final int startMs;
  final int endMs; // -1 = until the end
  final bool muted;
  const EditedVideo({required this.file, this.startMs = 0, this.endMs = -1, this.muted = false});

  bool get isTrimmed => startMs > 0 || endMs >= 0;
  bool get isEdited => isTrimmed || muted;
}

/// Telegram-like internal video editor: preview, trim start/end, mute toggle.
/// Returns an [EditedVideo] via Navigator.pop.
class VideoEditorScreen extends StatefulWidget {
  final File videoFile;
  const VideoEditorScreen({super.key, required this.videoFile});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _muted = false;
  double _start = 0; // seconds
  double _end = 0; // seconds (0 = full duration until ready)

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(widget.videoFile);
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (mounted) {
        setState(() {
          _ready = true;
          _end = c.value.duration.inMilliseconds / 1000.0;
        });
        c.play();
      }
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  String _fmt(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).round());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _done() {
    final total = _controller?.value.duration.inMilliseconds ?? 0;
    final endMs = (_end * 1000).round() >= total - 200 ? -1 : (_end * 1000).round();
    Navigator.pop(
      context,
      EditedVideo(
        file: widget.videoFile,
        startMs: (_start * 1000).round(),
        endMs: endMs,
        muted: _muted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ویرایش ویدیو'),
        actions: [
          IconButton(
            tooltip: _muted ? 'با صدا' : 'بی‌صدا',
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                color: _muted ? Colors.amber : Colors.white),
            onPressed: _ready ? _toggleMute : null,
          ),
          IconButton(
            tooltip: 'تأیید',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: _ready ? _done : null,
          ),
        ],
      ),
      body: !_ready || c == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(c),
                          GestureDetector(
                            onTap: () => setState(
                                () => c.value.isPlaying ? c.pause() : c.play()),
                            child: Container(
                              color: Colors.transparent,
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: c.value.isPlaying ? 0 : 0.8,
                                  duration: const Duration(milliseconds: 200),
                                  child: const CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  color: Colors.grey.shade900,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('شروع: ${_fmt(_start)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('پایان: ${_fmt(_end)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('مدت: ${_fmt(_end - _start)}',
                              style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Row(children: [
                        const Text('شروع', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: _start.clamp(0, _end),
                            min: 0,
                            max: _end,
                            onChanged: (v) => setState(() {
                              _start = v;
                              c.seekTo(Duration(milliseconds: (v * 1000).round()));
                            }),
                          ),
                        ),
                      ]),
                      Row(children: [
                        const Text('پایان', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: _end.clamp(_start, c.value.duration.inMilliseconds / 1000.0),
                            min: _start,
                            max: c.value.duration.inMilliseconds / 1000.0,
                            onChanged: (v) => setState(() {
                              _end = v;
                              c.seekTo(Duration(milliseconds: (v * 1000).round()));
                            }),
                          ),
                        ),
                      ]),
                      if (_muted)
                        const Row(children: [
                          Icon(Icons.volume_off, color: Colors.amber, size: 16),
                          SizedBox(width: 6),
                          Text('ویدیو بدون صدا ارسال می‌شود',
                              style: TextStyle(color: Colors.amber, fontSize: 12)),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
