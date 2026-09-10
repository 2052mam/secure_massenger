import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/models/message_model.dart';

/// Telegram-like location bubble: static preview + open-in-maps.
/// Live locations show remaining time and update via polling.
class LocationBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  const LocationBubble({super.key, required this.message, this.isMine = false});

  double? get _lat => message.latitude;
  double? get _lng => message.longitude;

  String get _mapsUrl {
    final lat = _lat ?? 0;
    final lng = _lng ?? 0;
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  String get _osmImage {
    final lat = _lat ?? 0;
    final lng = _lng ?? 0;
    // Free OpenStreetMap static preview (no API key needed).
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=15&size=400x220&maptype=mapnik&markers=$lat,$lng,red-pushpin';
  }

  Future<void> _openMaps(BuildContext context) async {
    final uri = Uri.parse(_mapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('امکان باز کردن نقشه وجود ندارد')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = isMine ? Colors.white : theme.colorScheme.onSurface;
    final live = message.isLiveLocation;
    final active = message.isLiveActive;
    return GestureDetector(
      onTap: () => _openMaps(context),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: (isMine ? Colors.white : Colors.black).withValues(alpha: 0.08),
          border: Border.all(color: fg.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  Image.network(
                    _osmImage,
                    height: 140,
                    width: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      color: Colors.grey.withValues(alpha: 0.2),
                      child: const Center(child: Icon(Icons.map_outlined, size: 40, color: Colors.grey)),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.location_on, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  if (live)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: active ? Colors.green : Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(active ? Icons.live_tv : Icons.timer_off_outlined, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            active ? 'زنده' : 'پایان یافته',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message.locationTitle?.isNotEmpty == true
                            ? message.locationTitle!
                            : (live ? 'لوکیشن زنده' : 'لوکیشن'),
                        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${(_lat ?? 0).toStringAsFixed(5)}, ${(_lng ?? 0).toStringAsFixed(5)}',
                    style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11),
                    textDirection: TextDirection.ltr,
                  ),
                  if (live && active && message.liveUntil != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'تا ${_two(message.liveUntil!.hour)}:${_two(message.liveUntil!.minute)} فعال است',
                      style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.open_in_new, size: 13, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('باز کردن در نقشه',
                        style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
