import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/models/gif_model.dart';
import '../../../data/services/api_service.dart';

class GifPicker extends StatefulWidget {
  final ApiService api;
  final ValueChanged<GifModel> onGifSelected;
  final ValueChanged<GifModel>? onGifSaved;
  const GifPicker({super.key, required this.api, required this.onGifSelected, this.onGifSaved});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  List<GifModel> _trending = [];
  List<GifModel> _saved = [];
  List<GifModel> _searchResults = [];
  final _searchCtrl = TextEditingController();
  int _tab = 0; //0 trending, 1 saved, 2 search
  bool _loading = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _loadSaved();
  }

  Future<void> _loadTrending() async {
    try {
      final res = await widget.api.get('/gifs/trending');
      final list = (res['gifs'] as List? ?? []).map((e) => GifModel.fromJson(e as Map<String, dynamic>)).toList();
      setState(() { _trending = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadSaved() async {
    try {
      final res = await widget.api.get('/gifs/saved');
      final list = (res['gifs'] as List? ?? []).map((e) => GifModel.fromJson(e as Map<String, dynamic>)).toList();
      setState(() { _saved = list; });
    } catch (_) {}
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; });
      return;
    }
    setState(() { _searching = true; });
    try {
      final res = await widget.api.get('/gifs/search', query: {'q': q});
      final list = (res['gifs'] as List? ?? []).map((e) => GifModel.fromJson(e as Map<String, dynamic>)).toList();
      setState(() { _searchResults = list; });
    } catch (_) {} finally {
      setState(() { _searching = false; });
    }
  }

  Future<void> _toggleSave(GifModel gif) async {
    final isSaved = _saved.any((g) => g.gifUrl == gif.gifUrl);
    if (isSaved) {
      final existing = _saved.firstWhere((g) => g.gifUrl == gif.gifUrl);
      await widget.api.post('/gifs/saved/${existing.id}', {});
      setState(() { _saved.removeWhere((g) => g.gifUrl == gif.gifUrl); });
    } else {
      await widget.api.post('/gifs/save', {'gif_url': gif.gifUrl, 'preview_url': gif.previewUrl, 'title': gif.title, 'external_id': gif.externalId});
      await _loadSaved();
      if (widget.onGifSaved != null) widget.onGifSaved!(gif);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گیف ذخیره شد')));
    }
  }

  Widget _grid(List<GifModel> items) {
    if (items.isEmpty) return const Center(child: Text('موردی یافت نشد'));
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final g = items[i];
        final saved = _saved.any((s) => s.gifUrl == g.gifUrl);
        return Stack(
          children: [
            GestureDetector(
              onTap: () => widget.onGifSelected(g),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey.withValues(alpha: 0.08)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: g.previewUrl ?? g.gifUrl ?? '',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorWidget: (_, __, ___) => const Center(child: Icon(Icons.gif_box_outlined)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _toggleSave(g),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 14, color: saved ? Colors.amber : Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'جستجوی گیف...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (v) {
                      setState(() { _tab = 2; });
                      _search(v);
                    },
                    onChanged: (v) {
                      if (v.length >= 2) _search(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); setState(() { _searchResults = []; _tab = 0; }); }),
              ],
            ),
          ),
          Row(
            children: [
              _tabButton('ترند', 0),
              _tabButton('ذخیره‌شده', 1),
              _tabButton('جستجو', 2),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _tab == 0
                        ? _grid(_trending)
                        : _tab == 1
                            ? _saved.isEmpty ? const Center(child: Text('هنوز گیفی ذخیره نکرده‌اید')) : _grid(_saved)
                            : _searching ? const Center(child: CircularProgressIndicator()) : _grid(_searchResults.isEmpty ? _trending : _searchResults),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                const Expanded(child: Text('برای ساخت گیف: ویدیو را انتخاب کنید و آن را به گیف تبدیل کنید (مانند تلگرام)', style: TextStyle(fontSize: 11, color: Colors.grey))),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // trigger video picker for GIF creation handled by parent
                  },
                  child: const Text('ساخت گیف', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int idx) {
    final selected = _tab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2))),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal, color: selected ? Theme.of(context).colorScheme.primary : Colors.grey)),
        ),
      ),
    );
  }
}
