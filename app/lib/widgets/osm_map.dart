import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';

/// Holds what the map shows. The pin is always the centre of the map.
class OsmMapController extends ChangeNotifier {
  OsmMapController({this.latitude = 11.1085, this.longitude = 77.3411, this.zoom = 17});

  double latitude;
  double longitude;
  double zoom;

  static const double minZoom = 4;
  static const double maxZoom = 19;

  void moveTo(double lat, double lng, {double? zoom}) {
    latitude = lat;
    longitude = lng;
    if (zoom != null) this.zoom = zoom.clamp(minZoom, maxZoom);
    notifyListeners();
  }

  void zoomBy(double delta) {
    zoom = (zoom + delta).clamp(minZoom, maxZoom);
    notifyListeners();
  }
}

/// A small, free OpenStreetMap view: drag to move, pinch or +/- to zoom.
/// Shows the GPS position (blue dot + accuracy circle) and a pin in the centre.
class OsmMap extends StatefulWidget {
  const OsmMap({
    super.key,
    required this.controller,
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsAccuracy,
    this.onUserMoved,
    this.onRecenter,
  });

  final OsmMapController controller;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final double? gpsAccuracy;

  /// Called when the person drags or zooms the map (the pin moved).
  final VoidCallback? onUserMoved;

  /// The "back to my position" button.
  final VoidCallback? onRecenter;

  @override
  State<OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<OsmMap> {
  double _startZoom = 0;

  OsmMapController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(OsmMap old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_changed);
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  // Web Mercator: world pixel coordinates at integer zoom z (256 px tiles).
  static double _x(double lng, int z) => (lng + 180) / 360 * 256 * (1 << z);
  static double _y(double lat, int z) {
    final r = lat.clamp(-85.0, 85.0) * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * 256 * (1 << z);
  }

  static double _lng(double x, int z) => x / (256 * (1 << z)) * 360 - 180;
  static double _lat(double y, int z) {
    final n = math.pi - 2 * math.pi * y / (256 * (1 << z));
    return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  int get _tileZoom => c.zoom.round();
  double get _scale => math.pow(2, c.zoom - _tileZoom).toDouble();

  void _onScaleStart(ScaleStartDetails d) => _startZoom = c.zoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final z = _tileZoom;
    final s = _scale;
    final cx = _x(c.longitude, z) - d.focalPointDelta.dx / s;
    final cy = _y(c.latitude, z) - d.focalPointDelta.dy / s;
    final zoom = (d.pointerCount > 1 && d.scale > 0) ? _startZoom + math.log(d.scale) / math.ln2 : null;
    c.moveTo(_lat(cy, z), _lng(cx, z), zoom: zoom); // notifies listeners
    widget.onUserMoved?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final z = _tileZoom;
        final s = _scale;
        final cx = _x(c.longitude, z), cy = _y(c.latitude, z);
        final n = 1 << z;

        Offset toScreen(double lat, double lng) =>
            Offset((_x(lng, z) - cx) * s + w / 2, (_y(lat, z) - cy) * s + h / 2);

        final tiles = <Widget>[];
        final x0 = ((cx - w / 2 / s) / 256).floor(), x1 = ((cx + w / 2 / s) / 256).floor();
        final y0 = ((cy - h / 2 / s) / 256).floor(), y1 = ((cy + h / 2 / s) / 256).floor();
        for (var ty = y0; ty <= y1; ty++) {
          if (ty < 0 || ty >= n) continue;
          for (var tx = x0; tx <= x1; tx++) {
            final wx = ((tx % n) + n) % n;
            final url = AppConfig.tileUrl
                .replaceAll('{z}', '$z')
                .replaceAll('{x}', '$wx')
                .replaceAll('{y}', '$ty');
            tiles.add(
              Positioned(
                key: ValueKey('$z/$tx/$ty'),
                left: (tx * 256 - cx) * s + w / 2,
                top: (ty * 256 - cy) * s + h / 2,
                width: 256 * s + 0.5,
                height: 256 * s + 0.5,
                child: Image.network(
                  url,
                  headers: const {'User-Agent': AppConfig.userAgent},
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE8ECE6)),
                ),
              ),
            );
          }
        }

        final overlays = <Widget>[];
        if (widget.gpsLatitude != null && widget.gpsLongitude != null) {
          final p = toScreen(widget.gpsLatitude!, widget.gpsLongitude!);
          final metersPerPx = 156543.03392 * math.cos(widget.gpsLatitude! * math.pi / 180) / n / s;
          final r = ((widget.gpsAccuracy ?? 0) / metersPerPx).clamp(8.0, 2000.0);
          overlays.add(
            Positioned(
              left: p.dx - r,
              top: p.dy - r,
              width: r * 2,
              height: r * 2,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VV.sky.withValues(alpha: 0.16),
                    border: Border.all(color: VV.sky, width: 1.5),
                  ),
                ),
              ),
            ),
          );
          overlays.add(
            Positioned(
              left: p.dx - 8,
              top: p.dy - 8,
              width: 16,
              height: 16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VV.blue,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
                  ),
                ),
              ),
            ),
          );
        }

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onDoubleTap: () {
                    c.zoomBy(1);
                    widget.onUserMoved?.call();
                  },
                  child: ColoredBox(
                    color: const Color(0xFFEEF1EC),
                    child: Stack(clipBehavior: Clip.none, children: [...tiles, ...overlays]),
                  ),
                ),
              ),
              // The pin: its tip marks the exact point that will be saved.
              Positioned(
                // The icon's tip sits ~46 px below its top edge.
                left: w / 2 - 22,
                top: h / 2 - 46,
                width: 44,
                height: 52,
                child: const IgnorePointer(child: _Pin()),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    _MapButton(icon: Icons.add, label: 'Zoom in', onTap: () => c.zoomBy(1)),
                    const SizedBox(height: 8),
                    _MapButton(icon: Icons.remove, label: 'Zoom out', onTap: () => c.zoomBy(-1)),
                  ],
                ),
              ),
              if (widget.onRecenter != null)
                Positioned(
                  right: 12,
                  bottom: 28,
                  child: _MapButton(
                    icon: Icons.my_location,
                    label: 'Move pin to my position',
                    onTap: widget.onRecenter!,
                    color: VV.blue,
                  ),
                ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  color: const Color(0xCCFFFFFF),
                  child: const Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10, color: VV.inkMuted),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          bottom: 0,
          child: Container(
            width: 12,
            height: 5,
            decoration: BoxDecoration(color: const Color(0x400F2A3F), borderRadius: BorderRadius.circular(6)),
          ),
        ),
        const Icon(
          Icons.location_on,
          size: 50,
          color: VV.blue,
          shadows: [Shadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        Positioned(
          top: 13,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: VV.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VV.radiusMd),
          side: const BorderSide(color: VV.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VV.radiusMd),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color ?? VV.ink, size: 22)),
        ),
      ),
    );
  }
}
