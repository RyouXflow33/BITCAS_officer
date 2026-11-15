import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
}

/// OSRM returns GeoJSON positions as longitude, then latitude.
RoadRoute? roadRouteFromOsrm(Map<String, dynamic> json) {
  final routes = json['routes'];
  if (routes is! List || routes.isEmpty || routes.first is! Map) return null;
  final route = Map<String, dynamic>.from(routes.first as Map);
  final geometry = route['geometry'];
  if (geometry is! Map) return null;
  final coords = geometry['coordinates'];
  if (coords is! List) return null;

  final points = <LatLng>[];
  for (final pair in coords) {
    if (pair is! List || pair.length < 2) continue;
    final lng = double.tryParse('${pair[0]}');
    final lat = double.tryParse('${pair[1]}');
    if (lat == null || lng == null) continue;
    points.add(LatLng(lat, lng));
  }
  if (points.length < 2) return null;

  return RoadRoute(
    points: points,
    distanceMeters: double.tryParse('${route['distance']}') ?? 0,
    durationSeconds: double.tryParse('${route['duration']}') ?? 0,
  );
}

String formatTrip(double meters, double seconds) {
  final distance = meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km'
      : '${meters.round()} m';
  final minutes = (seconds / 60).round();
  final eta = minutes < 1
      ? '<1 min'
      : minutes < 60
          ? '$minutes min'
          : '${minutes ~/ 60} h ${minutes % 60} min';
  return '$distance · $eta';
}

/// Driving route on OpenStreetMap roads. No straight line if the router is down.
Future<RoadRoute?> fetchDrivingRoute(LatLng from, LatLng to) async {
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/'
    '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
    '?overview=full&geometries=geojson&alternatives=false&steps=false',
  );
  final response = await http.get(uri, headers: const {
    'User-Agent': 'BITCAS-Officer/1.0 (bacolodlife.org)',
    'Accept': 'application/json',
  }).timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) return null;
  final decoded = jsonDecode(response.body);
  if (decoded is! Map || decoded['code'] != 'Ok') return null;
  return roadRouteFromOsrm(Map<String, dynamic>.from(decoded));
}
