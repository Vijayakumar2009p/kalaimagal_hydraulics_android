import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/customer.dart';
import '../services/app_state.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'location_saved_screen.dart';

/// Takes the phone's current location by itself, then offers "Save location".
///
/// It listens to GPS for up to [_maxWait] and keeps the most accurate reading.
/// It stops early as soon as the reading is good (20 m or better).
class SetLocationScreen extends StatefulWidget {
  const SetLocationScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<SetLocationScreen> createState() => _SetLocationScreenState();
}

class _SetLocationScreenState extends State<SetLocationScreen> {
  static const _maxWait = Duration(seconds: 15);

  StreamSubscription<Position>? _sub;
  Timer? _timer;
  Position? _best;
  DateTime? _capturedAt;
  bool _capturing = true;
  bool _timeUp = false;
  bool _mocked = false;
  bool _saving = false;
  LocationProblemException? _problem;

  @override
  void initState() {
    super.initState();
    Future.microtask(_capture); // after the first build (it calls setState)
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _capture() async {
    _stop();
    setState(() {
      _problem = null;
      _mocked = false;
      _best = null;
      _capturedAt = null;
      _capturing = true;
      _timeUp = false;
    });
    try {
      await LocationService.ensureReady(); // asks for permission when needed
    } on LocationProblemException catch (e) {
      if (mounted) setState(() => _problem = e);
      return;
    }
    if (!mounted) return;
    _timer = Timer(_maxWait, () {
      _timeUp = true;
      if (_best != null) _finish();
    });
    _sub = LocationService.positions().listen(
      _onPosition,
      onError: (Object e) {
        if (!mounted) return;
        _stop();
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
      _stop();
      setState(() => _mocked = true);
      return;
    }
    if (_best == null || p.accuracy < _best!.accuracy) setState(() => _best = p);
    if (p.accuracy <= AppConfig.goodAccuracyMeters || _timeUp) _finish();
  }

  void _finish() {
    _stop();
    if (mounted) {
      setState(() {
        _capturing = false;
        _capturedAt = DateTime.now();
      });
    }
  }

  bool get _good => _best != null && _best!.accuracy <= AppConfig.goodAccuracyMeters;

  Future<void> _save() async {
    final fix = _best;
    if (fix == null) return;
    final app = AppScope.read(context);
    final customer = app.resolve(widget.customer);

    if (customer.hasLocation) {
      final ok = await _confirmReplace(customer, fix);
      if (ok != true || !mounted) return;
    }

    setState(() => _saving = true);
    final input = LocationInput(
      customer: customer,
      latitude: double.parse(fix.latitude.toStringAsFixed(7)),
      longitude: double.parse(fix.longitude.toStringAsFixed(7)),
      accuracy: fix.accuracy,
      pinMovedMeters: 0,
      capturedAt: _capturedAt ?? DateTime.now(),
    );
    try {
      final ref = await app.saveLocation(input);
      HapticFeedback.mediumImpact(); // a short buzz: "done"
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

  Future<bool?> _confirmReplace(Customer c, Position fix) {
    final distance = distanceMeters(c.latitude, c.longitude, fix.latitude, fix.longitude);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace saved location?'),
        content: Text(
          '${c.name} already has a location'
          '${c.locationDate.isEmpty ? '' : ' (saved on ${formatOdooDate(c.locationDate)})'}.\n\n'
          'The new location is about ${formatMeters(distance)} from the saved one.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep saved')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
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
      body: SafeArea(child: _body(c)),
    );
  }

  Widget _body(Customer c) {
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
        onPressed: _capture,
      );
    }
    final problem = _problem;
    if (problem != null) {
      return _Blocker(
        icon: Icons.gps_off,
        tone: Tone.gold,
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
          await _capture();
        },
        secondaryLabel: 'Try again',
        onSecondary: _capture,
      );
    }
    return _capturing ? _capturingView() : _capturedView();
  }

  Widget _capturingView() {
    final best = _best;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          const SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(child: CircularProgressIndicator(strokeWidth: 3, color: VV.blue)),
                Icon(Icons.my_location, size: 40, color: VV.blue),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Getting your current location…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            best == null
                ? 'Stay at the customer location. This takes a few seconds.'
                : 'Accuracy so far: ${best.accuracy.round()} m',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: VV.inkMuted),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _capturedView() {
    final fix = _best;
    if (fix == null) {
      // Time ran out without any GPS reading (still waiting for the first one).
      return _capturingView();
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            children: [
              const _Steps(),
              const SizedBox(height: 24),
              Center(child: BigIcon(Icons.location_on, tone: _good ? Tone.blue : Tone.gold)),
              const SizedBox(height: 16),
              const Text(
                'Location found',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: VV.goldSoft,
                    borderRadius: BorderRadius.circular(VV.radiusMd),
                  ),
                  child: const Text(
                    'Not saved yet. Tap the blue button below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: VV.goldText),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              InfoTable([
                ('Latitude', formatCoord(fix.latitude)),
                ('Longitude', formatCoord(fix.longitude)),
                ('Accuracy', '${fix.accuracy.round()} m${_good ? ' (good)' : ' (approximate)'}'),
                ('Time', _capturedAt == null ? '' : formatDateTime(_capturedAt!)),
              ]),
              if (!_good) ...[
                const SizedBox(height: 16),
                Callout(
                  'GPS is weak here (${fix.accuracy.round()} m). For a more exact location, step outside '
                  'or near a window and tap "Find again".',
                  tone: Tone.gold,
                  icon: Icons.info_outline,
                ),
              ],
              const SizedBox(height: 16),
              const Icon(Icons.keyboard_double_arrow_down, size: 36, color: VV.blue),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: VV.blueSoft,
            border: Border(top: BorderSide(color: VV.line)),
          ),
          child: Column(
            children: [
              _Pulse(
                active: !_saving,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      elevation: 3,
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.save_alt, size: 26),
                    label: Text(_saving ? 'Saving…' : 'Save location'),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _saving ? null : _capture,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Find again'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "1 Find location ✓  ——  2 Save" so the person knows one step is left.
class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String label, {required bool done}) => Column(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: done ? VV.success : VV.blue, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : Text(
                  n,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: done ? FontWeight.w500 : FontWeight.w700,
            color: done ? VV.inkMuted : VV.blue,
          ),
        ),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step('1', 'Find location', done: true),
        Container(
          width: 64,
          height: 2,
          margin: const EdgeInsets.only(top: 17, left: 8, right: 8),
          color: VV.line,
        ),
        step('2', 'Save', done: false),
      ],
    );
  }
}

/// Gently grows and shrinks its child to draw the eye (the Save button).
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child, this.active = true});
  final Widget child;
  final bool active;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.04).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
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
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
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
