import 'dart:math' as math;

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

class Sector {
  const Sector(this.name, this.district, this.lat, this.lng);
  final String name;
  final String district;
  final double lat;
  final double lng;

  String get label => '$name ($district)';
  LatLng get point => LatLng(lat, lng);
}

/// Kigali sectors used for the client's location (no GPS package needed).
const kigaliSectors = <Sector>[
  Sector('Remera', 'Gasabo', -1.9536, 30.1131),
  Sector('Kimironko', 'Gasabo', -1.9420, 30.1250),
  Sector('Kacyiru', 'Gasabo', -1.9380, 30.0890),
  Sector('Kimihurura', 'Gasabo', -1.9530, 30.0950),
  Sector('Nyarutarama', 'Gasabo', -1.9330, 30.1050),
  Sector('Gisozi', 'Gasabo', -1.9240, 30.0640),
  Sector('Kiyovu', 'Nyarugenge', -1.9480, 30.0650),
  Sector('Nyamirambo', 'Nyarugenge', -1.9710, 30.0480),
  Sector('Nyarugenge (CBD)', 'Nyarugenge', -1.9450, 30.0590),
  Sector('Gikondo', 'Kicukiro', -1.9670, 30.0810),
  Sector('Kicukiro', 'Kicukiro', -1.9780, 30.1000),
  Sector('Kanombe', 'Kicukiro', -1.9680, 30.1400),
  Sector('Niboye', 'Kicukiro', -1.9800, 30.1170),
];

Sector sectorByName(String? name) {
  if (name != null) {
    for (final s in kigaliSectors) {
      if (name.toLowerCase().startsWith(s.name.toLowerCase())) return s;
    }
  }
  return kigaliSectors.first;
}

Sector nearestSector(double lat, double lng) {
  var best = kigaliSectors.first;
  var bestD = double.infinity;
  for (final s in kigaliSectors) {
    final d = distanceKm(lat, lng, s.lat, s.lng);
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return best;
}

double _rad(double d) => d * math.pi / 180;

double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Bearing in radians (0 = north, clockwise).
double bearing(double lat1, double lng1, double lat2, double lng2) {
  final y = math.sin(_rad(lng2 - lng1)) * math.cos(_rad(lat2));
  final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) -
      math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(_rad(lng2 - lng1));
  return math.atan2(y, x);
}
