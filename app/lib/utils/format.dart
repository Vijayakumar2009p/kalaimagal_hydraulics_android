import 'dart:math' as math;

String _two(int n) => n.toString().padLeft(2, '0');

/// 05-11-2026
String formatDate(DateTime d) => '${_two(d.day)}-${_two(d.month)}-${d.year}';

/// 05-11-2026, 10:42
String formatDateTime(DateTime d) => '${formatDate(d)}, ${_two(d.hour)}:${_two(d.minute)}';

/// 10:42
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Odoo date "2026-11-05" -> "05-11-2026"
String formatOdooDate(String odoo) {
  final d = DateTime.tryParse(odoo);
  return d == null ? odoo : formatDate(d);
}

/// For Odoo date fields: "2026-11-05"
String odooDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Indian number format: 125000 -> "1,25,000"
String formatIndian(int n) {
  final s = n.abs().toString();
  if (s.length <= 3) return '${n < 0 ? '-' : ''}$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${n < 0 ? '-' : ''}${groups.join(',')},$last3';
}

String formatCoord(double v) => v.toStringAsFixed(7);

String formatMeters(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
  return '${m.round()} m';
}

/// Distance in metres between two points (haversine).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// "1.2.0" > "1.10.0"? Returns positive when a > b.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < math.max(pa.length, pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}
