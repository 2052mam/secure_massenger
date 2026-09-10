import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// Telegram-like internal photo editor: crop (aspect ratios), rotate, flip,
/// draw (pen colors/sizes), text overlay, then send.
/// Returns the edited [File] via Navigator.pop.
class PhotoEditorScreen extends StatefulWidget {
  final File imageFile;
  const PhotoEditorScreen({super.key, required this.imageFile});

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _DrawStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  _DrawStroke({required this.points, required this.color, required this.width});
}

class _TextOverlay {
  String text;
  Offset position;
  Color color;
  double size;
  _TextOverlay({required this.text, required this.position, required this.color, required this.size});
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _repaintKey = GlobalKey();
  Uint8List? _baseBytes;
  img.Image? _baseImage;
  bool _loading = true;

  // Crop
  double? _aspectRatio; // null = free
  // Transform
  int _quarterTurns = 0;
  bool _flipH = false;
  // Draw
  final List<_DrawStroke> _strokes = [];
  List<Offset>? _currentStroke;
  Color _penColor = Colors.red;
  double _penWidth = 4;
  bool _drawing = true;
  // Text
  final List<_TextOverlay> _texts = [];

  static const _colors = [Colors.red, Colors.white, Colors.black, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.orange];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (mounted) {
        setState(() {
          _baseBytes = bytes;
          _baseImage = decoded;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rotate() {
    final base = _baseImage;
    if (base == null) return;
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _baseImage = img.copyRotate(base, angle: 90);
      _strokes.clear();
      _texts.clear();
    });
  }

  void _flip() {
    final base = _baseImage;
    if (base == null) return;
    setState(() {
      _flipH = !_flipH;
      _baseImage = img.flipHorizontal(base);
      _strokes.clear();
      _texts.clear();
    });
  }

  void _applyCrop(double? ratio) {
    final base = _baseImage;
    if (base == null) return;
    if (ratio == null) {
      setState(() => _aspectRatio = null);
      return;
    }
    // Center-crop to the requested aspect ratio.
    final w = base.width.toDouble();
    final h = base.height.toDouble();
    double cw = w, ch = h;
    if (w / h > ratio) {
      cw = h * ratio;
    } else {
      ch = w / ratio;
    }
    final x = ((w - cw) / 2).round();
    final y = ((h - ch) / 2).round();
    setState(() {
      _aspectRatio = ratio;
      _baseImage = img.copyCrop(base, x: x, y: y, width: cw.round(), height: ch.round());
      _strokes.clear();
      _texts.clear();
    });
  }

  Future<void> _addText() async {
    final ctrl = TextEditingController();
    Color color = Colors.white;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('متن روی عکس'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'متن...')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _colors.map((c) => GestureDetector(
                      onTap: () => setD(() => color = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: color == c ? Colors.blue : Colors.grey, width: color == c ? 3 : 1),
                        ),
                      ),
                    )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('افزودن')),
          ],
        ),
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _texts.add(_TextOverlay(text: text, position: const Offset(60, 120), color: color, size: 32)));
  }

  Future<void> _save() async {
    try {
      // Render the drawing layer + base image into one file.
      final base = _baseImage;
      if (base == null) {
        Navigator.pop(context, widget.imageFile);
        return;
      }
      // 1) Bake base transform into bytes.
      var out = img.encodeJpg(base, quality: 92);
      // 2) If there are strokes/texts, composite via RepaintBoundary screenshot
      //    scaled back to the base size.
      if (_strokes.isNotEmpty || _texts.isNotEmpty) {
        final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data != null) {
            final shot = img.decodeImage(data.buffer.asUint8List());
            if (shot != null) {
              final resized = img.copyResize(shot, width: base.width, height: base.height);
              out = Uint8List.fromList(img.encodeJpg(resized, quality: 92));
            }
          }
        }
      }
      final path = '${widget.imageFile.parent.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await File(path).writeAsBytes(out);
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره ناموفق: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ویرایش عکس'),
        actions: [
          IconButton(tooltip: 'چرخش', icon: const Icon(Icons.rotate_right), onPressed: _rotate),
          IconButton(tooltip: 'آینه', icon: const Icon(Icons.flip), onPressed: _flip),
          IconButton(tooltip: 'متن', icon: const Icon(Icons.text_fields), onPressed: _addText),
          IconButton(tooltip: 'پاک کردن نقاشی', icon: const Icon(Icons.undo), onPressed: () => setState(() {
                if (_currentStroke == null && _strokes.isNotEmpty) _strokes.removeLast();
              })),
          IconButton(tooltip: 'ارسال', icon: const Icon(Icons.check, color: Colors.green), onPressed: _save),
        ],
      ),
      body: _loading || _baseBytes == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                // Crop bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    _cropChip('آزاد', null),
                    _cropChip('۱:۱', 1.0),
                    _cropChip('۴:۳', 4 / 3),
                    _cropChip('۱۶:۹', 16 / 9),
                    _cropChip('۹:۱۶', 9 / 16),
                  ]),
                ),
                Expanded(
                  child: Center(
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          children: [
                            Image.memory(
                              Uint8List.fromList(img.encodeJpg(_baseImage!, quality: 90)),
                              fit: BoxFit.contain,
                            ),
                            Positioned.fill(
                              child: GestureDetector(
                                onPanStart: _drawing ? (d) => setState(() => _currentStroke = [d.localPosition]) : null,
                                onPanUpdate: _drawing ? (d) => setState(() => _currentStroke?.add(d.localPosition)) : null,
                                onPanEnd: _drawing
                                    ? (_) {
                                        if (_currentStroke != null && _currentStroke!.length > 1) {
                                          _strokes.add(_DrawStroke(
                                              points: List.of(_currentStroke!), color: _penColor, width: _penWidth));
                                        }
                                        setState(() => _currentStroke = null);
                                      }
                                    : null,
                                child: CustomPaint(
                                  painter: _DrawPainter(
                                    strokes: [..._strokes, if (_currentStroke != null) _DrawStroke(points: _currentStroke!, color: _penColor, width: _penWidth)],
                                  ),
                                  child: Stack(
                                    children: _texts.map((t) => Positioned(
                                          left: t.position.dx,
                                          top: t.position.dy,
                                          child: GestureDetector(
                                            onPanUpdate: (d) => setState(() => t.position += d.delta),
                                            onDoubleTap: () => setState(() => _texts.remove(t)),
                                            child: Text(t.text,
                                                style: TextStyle(
                                                    color: t.color,
                                                    fontSize: t.size,
                                                    fontWeight: FontWeight.w700,
                                                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
                                          ),
                                        )).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Pen colors + width
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: _drawing ? 'حالت مشاهده' : 'حالت نقاشی',
                            icon: Icon(_drawing ? Icons.brush : Icons.pan_tool_outlined, color: Colors.white),
                            onPressed: () => setState(() => _drawing = !_drawing),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: _colors.map((c) => GestureDetector(
                                    onTap: () => setState(() {
                                      _penColor = c;
                                      _drawing = true;
                                    }),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      decoration: BoxDecoration(
                                        color: c,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: _penColor == c ? Colors.blue : Colors.white30,
                                            width: _penColor == c ? 3 : 1),
                                      ),
                                    ),
                                  )).toList(),
                            ),
                          ),
                        ],
                      ),
                      Row(children: [
                        const Text('ضخامت', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: _penWidth,
                            min: 2,
                            max: 20,
                            onChanged: (v) => setState(() => _penWidth = v),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _cropChip(String label, double? ratio) {
    final selected = _aspectRatio == ratio;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70)),
        selected: selected,
        selectedColor: Colors.blue,
        backgroundColor: Colors.white10,
        onSelected: (_) => _applyCrop(ratio),
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  final List<_DrawStroke> strokes;
  _DrawPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], paint);
      }
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) => true;
}
