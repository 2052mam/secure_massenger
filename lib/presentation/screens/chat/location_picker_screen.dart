import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Telegram-like location picker: current GPS location or manual coordinates.
/// Returns (latitude, longitude, title, isLive, liveMinutes) via Navigator.pop.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _loadingGps = false;
  bool _isLive = false;
  int _liveMinutes = 15;
  String? _error;

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loadingGps = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('دسترسی لوکیشن داده نشد. مختصات را دستی وارد کنید.');
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _latCtrl.text = pos.latitude.toStringAsFixed(6);
          _lngCtrl.text = pos.longitude.toStringAsFixed(6);
          _loadingGps = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString(), _loadingGps = false);
    }
  }

  void _submit() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      setState(() => _error = 'مختصات نامعتبر است (عرض: -90..90، طول: -180..180)');
      return;
    }
    Navigator.pop(context, {
      'latitude': lat,
      'longitude': lng,
      'title': _titleCtrl.text.trim(),
      'is_live': _isLive,
      'live_minutes': _liveMinutes,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ارسال لوکیشن')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.location_on_outlined, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'لوکیشن خود را ارسال کنید. می‌توانید از GPS استفاده کنید یا مختصات را دستی وارد کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadingGps ? null : _useCurrentLocation,
              icon: _loadingGps
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location, size: 18),
              label: Text(_loadingGps ? 'در حال دریافت...' : 'استفاده از لوکیشن فعلی (GPS)'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'عرض جغرافیایی (Lat)',
                    hintText: '35.6892',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'طول جغرافیایی (Lng)',
                    hintText: '51.3890',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'عنوان (اختیاری)',
                hintText: 'مثلاً: کافه، منزل، محل قرار...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _isLive,
              onChanged: (v) => setState(() => _isLive = v),
              title: const Text('لوکیشن زنده (Live)'),
              subtitle: const Text('موقعیت شما با polling به‌روزرسانی می‌شود', style: TextStyle(fontSize: 11, color: Colors.grey)),
              secondary: const Icon(Icons.live_tv, color: Colors.green),
            ),
            if (_isLive)
              DropdownButtonFormField<int>(
                initialValue: _liveMinutes,
                decoration: const InputDecoration(labelText: 'مدت اشتراک زنده', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('۱۵ دقیقه')),
                  DropdownMenuItem(value: 60, child: Text('۱ ساعت')),
                  DropdownMenuItem(value: 480, child: Text('۸ ساعت')),
                ],
                onChanged: (v) => setState(() => _liveMinutes = v ?? 15),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('ارسال لوکیشن'),
            ),
          ],
        ),
      ),
    );
  }
}
