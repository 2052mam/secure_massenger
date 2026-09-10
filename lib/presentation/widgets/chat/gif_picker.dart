import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/models/gif_model.dart';
import '../../../data/services/api_service.dart';

/// Simplified Telegram-like GifPicker:
/// - No online/trending network fetch – user asked to remove it (was crashing / unwanted).
/// - Only shows saved GIFs (media_id based) + "make GIF from video" via upload.
class GifPicker extends StatefulWidget {
  final ApiService api;
  final ValueChanged<GifModel> onGifSelected;
  final ValueChanged<GifModel>? onGifSaved;
  const GifPicker({super.key, required this.api, required this.onGifSelected, this.onGifSaved});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  List<GifModel> _saved = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.get('/gifs/saved');
      final list = (res['gifs'] as List? ?? []).map((e) => GifModel.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() { _saved = list; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _unsave(GifModel gif) async {
    try {
      await widget.api.post('/gifs/saved/${gif.id}', {});
      setState(() => _saved.removeWhere((g) => g.id == gif.id));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گیف از ذخیره حذف شد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _grid() {
    if (_saved.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gif_box_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('هنوز گیفی ذخیره نکرده‌اید', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('با «ساخت GIF از ویدیو» یک ویدیو را به گیف تبدیل و ذخیره کنید.\nسپس همین‌جا آن را ارسال کنید.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _loadSaved, icon: const Icon(Icons.refresh, size: 18), label: const Text('بروزرسانی')),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.95),
      itemCount: _saved.length,
      itemBuilder: (ctx, i) {
        final g = _saved[i];
        final url = g.gifUrl ?? g.previewUrl ?? '';
        return Stack(
          children: [
            GestureDetector(
              onTap: () => widget.onGifSelected(g),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.grey.withValues(alpha: 0.08), border: Border.all(color: Colors.grey.withValues(alpha: 0.12))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: url.isEmpty
                      ? const Center(child: Icon(Icons.gif, size: 36, color: Colors.grey))
                      : CachedNetworkImage(
                          imageUrl: url.startsWith('/') ? '' : url, // relative media URLs are not image URLs for CDN; show placeholder
                          // For media_id-based gifs, previewUrl may be empty; we show an icon and title instead.
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          errorWidget: (_, __, ___) => Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.gif, size: 28, color: Colors.blue),
                              const SizedBox(height: 4),
                              Text(g.title ?? 'GIF', style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center, maxLines: 2),
                            ]),
                          ),
                        ),
                ),
              ),
            ),
            // title overlay when using local media (no external url)
            if (url.isEmpty || url.startsWith('/'))
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => widget.onGifSelected(g),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.gif, color: Colors.white, size: 22),
                        const SizedBox(height: 4),
                        Text(g.title ?? 'GIF ذخیره‌شده', style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _unsave(g),
                child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.delete_outline, size: 14, color: Colors.white)),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)), child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 460,
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              const Icon(Icons.gif_box_outlined, color: Colors.blue),
              const SizedBox(width: 8),
              const Expanded(child: Text('گیف‌ها (ذخیره‌شده)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              IconButton(tooltip: 'بروزرسانی', onPressed: _loadSaved, icon: const Icon(Icons.refresh, size: 20)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)))) : _grid()),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              const Expanded(child: Text('گیف‌های آنلاین حذف شده. با انتخاب «ساخت GIF از ویدیو» در منوی پیوست، ویدیو را به گیف تبدیل و همین‌جا ارسال کنید (مانند تلگرام).', style: TextStyle(fontSize: 11, color: Colors.grey))),
            ]),
          ),
        ],
      ),
    );
  }
}
