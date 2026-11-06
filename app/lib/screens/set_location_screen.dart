import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/customer.dart';
import '../services/app_state.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import '../widgets/osm_map.dart';
import 'location_saved_screen.dart';

class SetLocationScreen extends StatefulWidget {
  const SetLocationScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<SetLocationScreen> createState() => _SetLocationScreenState();
}

class _SetLocationScreenState extends State<SetLocationScreen> {
  late final OsmMapController _map;
  StreamSubscription<Position>? _sub;
  Timer? _ticker;

  Position? _fix;
  LocationProblemException? _problem;
  bool _mocked = false;
  bool _follow = true;
  bool _firstFix = true;
  bool _starting = true;
  late DateTime _startedAt;

  // Address
  final _street = TextEditingController();
  final _street2 = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  late final Customer _original;
  GpsAddress? _gpsAddress;
  bool _gpsAddressUsed = false;
  bool _lookingUpAddress = false;
  bool _autoLookupDone = false;

  final _remark = TextEditingController();
  String? _photoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _original = AppScope.read(context).resolve(widget.customer);
    _street.text = _original.street;
    _street2.text = _original.street2;
    _city.text = _original.city;
    _zip.text = _original.zip;
    _map = _original.hasLocation
        ? OsmMapController(latitude: _original.latitude, longitude: _original.longitude, zoom: 18)
        : OsmMapController(zoom: 15);
    Future.microtask(_start); // after the first build (it calls setState)
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _map.dispose();
    for (final c in [_street, _street2, _city, _zip, _remark]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    _sub?.cancel();
    setState(() {
      _problem = null;
      _mocked = false;
      _starting = true;
      _fix = null;
      _follow = true;
      _firstFix = true;
    });
    try {
      await LocationService.ensureReady();
    } on LocationProblemException catch (e) {
      if (mounted) setState(() => _problem = e);
      return;
    } finally {
      if (mounted) setState(() => _starting = false);
    }
    _startedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_isGood) setState(() {});
    });
    _sub = LocationService.positions().listen(
      _onPosition,
      onError: (Object e) {
        if (!mounted) return;
        setState(
          () => _problem = LocationProblemException(
            e is PermissionDeniedException ? LocationProblem.denied : LocationProblem.serviceOff,
          ),
        );
      },
    );
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    if (p.isMocked) {
      _sub?.cancel();
      setState(() => _mocked = true);
      return;
    }
    setState(() => _fix = p);
    if (_follow) {
      _map.moveTo(p.latitude, p.longitude, zoom: _firstFix ? 18 : null);
    }
    _firstFix = false;
    // Suggest an address once (fills the fields only if they are empty).
    if (!_autoLookupDone && p.accuracy <= 50) {
      _autoLookupDone = true;
      _lookupAddress(fillIfEmpty: true);
    }
  }

  bool get _isGood => _fix != null && _fix!.accuracy <= AppConfig.goodAccuracyMeters;
  Duration get _elapsed => DateTime.now().difference(_startedAt);
  bool get _canSaveAnyway => _fix != null && _elapsed >= AppConfig.saveAnywayAfter;

  double get _pinMoved =>
      _fix == null ? 0 : distanceMeters(_fix!.latitude, _fix!.longitude, _map.latitude, _map.longitude);

  Future<void> _lookupAddress({required bool fillIfEmpty}) async {
    setState(() => _lookingUpAddress = true);
    final a = await LocationService.addressFor(_map.latitude, _map.longitude);
    if (!mounted) return;
    setState(() {
      _lookingUpAddress = false;
      _gpsAddress = a;
    });
    if (a == null || a.isEmpty) {
      if (!fillIfEmpty) showMessage(context, 'No address found for this point (needs internet).');
      return;
    }
    final empty = _street.text.trim().isEmpty && _city.text.trim().isEmpty && _zip.text.trim().isEmpty;
    if (!fillIfEmpty || empty) _useGpsAddress(a);
  }

  void _useGpsAddress(GpsAddress a) {
    setState(() {
      _street.text = a.street;
      _street2.text = a.street2;
      _city.text = a.city;
      _zip.text = a.zip;
      _gpsAddressUsed = true;
    });
  }

  Map<String, String>? _changedAddress() {
    final now = [_street.text.trim(), _street2.text.trim(), _city.text.trim(), _zip.text.trim()];
    final before = [_original.street, _original.street2, _original.city, _original.zip];
    var changed = false;
    for (var i = 0; i < now.length; i++) {
      if (now[i] != before[i].trim()) changed = true;
    }
    if (!changed) return null;
    return {
      'street': now[0],
      'street2': now[1],
      'city': now[2],
      'zip': now[3],
      'state': _gpsAddressUsed ? (_gpsAddress?.state ?? '') : '',
      'countryCode': _gpsAddressUsed ? (_gpsAddress?.countryCode ?? '') : '',
    };
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );
      if (photo != null && mounted) setState(() => _photoPath = photo.path);
    } on PlatformException catch (e) {
      if (mounted) showMessage(context, 'Camera not available: ${e.message ?? e.code}', error: true);
    }
  }

  Future<void> _save() async {
    final fix = _fix;
    if (fix == null) return;
    FocusScope.of(context).unfocus();
    final zipError = Validators.pinError(_zip.text);
    if (zipError != null) {
      showMessage(context, 'PIN code must be 6 digits.', error: true);
      return;
    }
    final app = AppScope.read(context);
    final customer = app.resolve(widget.customer);
    final lat = _map.latitude, lng = _map.longitude;

    if (customer.hasLocation) {
      final ok = await _confirmReplace(customer, lat, lng, fix.accuracy);
      if (ok != true || !mounted) return;
    }

    setState(() => _saving = true);
    final input = LocationInput(
      customer: customer,
      latitude: double.parse(lat.toStringAsFixed(7)),
      longitude: double.parse(lng.toStringAsFixed(7)),
      accuracy: fix.accuracy,
      pinMovedMeters: _pinMoved,
      capturedAt: DateTime.now(),
      address: _changedAddress(),
      remark: _remark.text,
      photoPath: _photoPath,
    );
    try {
      final ref = await app.saveLocation(input);
      if (!mounted) return;
      await _sub?.cancel();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LocationSavedScreen(input: input, entryRef: ref),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e', error: true);
      }
    }
  }

  Future<bool?> _confirmReplace(Customer c, double lat, double lng, double accuracy) {
    final distance = distanceMeters(c.latitude, c.longitude, lat, lng);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace saved location?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${c.name} already has a location${c.pending ? ' waiting to sync' : ' in Odoo'}.',
              style: const TextStyle(color: VV.inkMuted),
            ),
            const SizedBox(height: 16),
            _compareBox(
              'SAVED',
              '${formatCoord(c.latitude)}, ${formatCoord(c.longitude)}',
              c.locationDate.isEmpty ? '' : 'Saved on ${formatOdooDate(c.locationDate)}',
              false,
            ),
            _compareBox(
              'NEW',
              '${formatCoord(lat)}, ${formatCoord(lng)}',
              'About ${formatMeters(distance)} from the saved point · GPS ${accuracy.round()} m',
              true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep saved')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
        ],
      ),
    );
  }

  Widget _compareBox(String label, String coords, String note, bool highlight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? VV.blueSoft : VV.surface,
        border: Border.all(color: highlight ? VV.blueSoft : VV.line),
        borderRadius: BorderRadius.circular(VV.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight ? VV.blue : VV.inkMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(coords, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 12, color: VV.inkMuted)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).resolve(widget.customer);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set location'),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: VV.inkMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_mocked) {
      return _Blocker(
        icon: Icons.location_off_outlined,
        title: 'Fake GPS detected',
        message: 'This phone is using a mock location app, so the location cannot be saved.',
        steps: const [
          'Close or uninstall any fake GPS app.',
          'Open Settings › Developer options › Select mock location app, and choose "Nothing".',
          'Come back and tap Try again.',
        ],
        buttonLabel: 'Try again',
        onPressed: _start,
      );
    }
    final problem = _problem;
    if (problem != null) {
      return _Blocker(
        icon: Icons.gps_off,
        title: switch (problem.problem) {
          LocationProblem.serviceOff => 'Turn on location',
          LocationProblem.approximate => 'Precise location needed',
          _ => 'Location permission needed',
        },
        message: problem.message,
        buttonLabel: switch (problem.problem) {
          LocationProblem.serviceOff => 'Open location settings',
          LocationProblem.deniedForever || LocationProblem.approximate => 'Open app settings',
          LocationProblem.denied => 'Allow location',
        },
        onPressed: () async {
          if (problem.problem == LocationProblem.serviceOff) {
            await LocationService.openLocationSettings();
          } else if (problem.problem == LocationProblem.deniedForever ||
              problem.problem == LocationProblem.approximate) {
            await LocationService.openAppSettings();
          }
          await _start();
        },
        secondaryLabel: 'Try again',
        onSecondary: _start,
        tone: Tone.gold,
      );
    }
    if (_starting) return const Center(child: CircularProgressIndicator(color: VV.blue));

    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      children: [
        SizedBox(
          height: keyboard ? 150 : 290,
          child: Stack(
            children: [
              Positioned.fill(
                child: OsmMap(
                  controller: _map,
                  gpsLatitude: _fix?.latitude,
                  gpsLongitude: _fix?.longitude,
                  gpsAccuracy: _fix?.accuracy,
                  onUserMoved: () {
                    if (_follow) setState(() => _follow = false);
                  },
                  onRecenter: () {
                    setState(() => _follow = true);
                    final f = _fix;
                    if (f != null) _map.moveTo(f.latitude, f.longitude, zoom: 18);
                  },
                ),
              ),
              if (!keyboard)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 64,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: VV.surface,
                        borderRadius: BorderRadius.circular(VV.radiusMd),
                        boxShadow: const [BoxShadow(color: Color(0x220F2A3F), blurRadius: 3)],
                      ),
                      child: Text(
                        _follow ? 'Move the map to put the pin on the entrance' : 'Pin placed by you',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              ListenableBuilder(
                listenable: _map,
                builder: (context, _) => Column(
                  children: [
                    _accuracyBar(),
                    if (_pinMoved > AppConfig.pinMoveWarningMeters) ...[
                      const SizedBox(height: 10),
                      Callout(
                        'The pin is ${formatMeters(_pinMoved)} from your GPS position. '
                        'Make sure it is on the right building.',
                        tone: Tone.gold,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text('Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: _lookingUpAddress ? null : () => _lookupAddress(fillIfEmpty: false),
                    icon: _lookingUpAddress
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.place_outlined, size: 18),
                    label: const Text('Fill from pin'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _street,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Door no., street', labelText: 'Street'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _street2,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Area / locality', labelText: 'Area'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _zip,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(labelText: 'PIN code'),
                    ),
                  ),
                ],
              ),
              if (_gpsAddressUsed)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Address suggested from GPS. Please check and correct it.',
                    style: TextStyle(fontSize: 12, color: VV.inkMuted),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _photoTile(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _remark,
                      maxLength: 200,
                      decoration: const InputDecoration(hintText: 'Remark (optional)', counterText: ''),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: VV.line)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
              onPressed: _saving || !(_isGood || _canSaveAnyway) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_saveLabel(), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }

  String _saveLabel() {
    if (_fix == null) return 'Waiting for GPS…';
    if (_isGood) return 'Save location';
    if (_canSaveAnyway) return 'Save anyway (GPS ${_fix!.accuracy.round()} m)';
    final left = AppConfig.saveAnywayAfter - _elapsed;
    return 'Waiting for better GPS… ${left.inSeconds}s';
  }

  Widget _accuracyBar() {
    final fix = _fix;
    final (Tone tone, IconData icon, String text) = fix == null
        ? (Tone.neutral, Icons.satellite_alt_outlined, 'Finding your position…')
        : _isGood
        ? (Tone.success, Icons.check_circle_outline, 'Good GPS · ${fix.accuracy.round()} m')
        : (
            Tone.gold,
            Icons.warning_amber_rounded,
            'Weak GPS · ${fix.accuracy.round()} m. Step outside or wait.',
          );
    final colors = switch (tone) {
      Tone.success => (VV.successSoft, VV.success),
      Tone.gold => (VV.goldSoft, VV.goldText),
      _ => (VV.surfaceRaised, VV.inkMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(VV.radiusMd)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.$2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: colors.$2, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          Text(
            '${_map.latitude.toStringAsFixed(5)}, ${_map.longitude.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 12, color: VV.ink, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _photoTile() {
    if (_photoPath == null) {
      return OutlinedButton.icon(
        onPressed: _takePhoto,
        icon: const Icon(Icons.photo_camera_outlined, size: 18),
        label: const Text('Photo'),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(VV.radiusMd),
          child: Image.file(File(_photoPath!), width: 56, height: 48, fit: BoxFit.cover),
        ),
        Positioned(
          right: -10,
          top: -10,
          child: IconButton(
            tooltip: 'Remove photo',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: VV.ink, foregroundColor: Colors.white),
            iconSize: 14,
            onPressed: () => setState(() => _photoPath = null),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}

/// Full-screen stop (fake GPS, GPS off, permission missing).
class _Blocker extends StatelessWidget {
  const _Blocker({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.steps = const [],
    this.secondaryLabel,
    this.onSecondary,
    this.tone = Tone.danger,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> steps;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          BigIcon(icon, tone: tone, round: false),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.5, color: VV.inkMuted),
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VV.surfaceRaised,
                border: Border.all(color: VV.line),
                borderRadius: BorderRadius.circular(VV.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('To fix it', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${i + 1}. ${steps[i]}', style: const TextStyle(height: 1.4)),
                    ),
                ],
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}
