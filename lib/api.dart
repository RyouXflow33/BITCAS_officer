import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class AuthException implements Exception {}

String? _blankToNull(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

class OfficerCase {
  const OfficerCase({
    required this.assignmentId,
    required this.status,
    required this.nextStatus,
    required this.reportId,
    required this.location,
    required this.congestionScore,
    required this.vehicleCount,
    required this.lat,
    required this.lng,
    required this.snapshotUrl,
    this.level,
    this.assignedAtIso,
    this.enrouteAtIso,
    this.onsceneAtIso,
  });

  final String assignmentId;
  final String status;
  final String? nextStatus;
  final String reportId;
  final String location;
  final int congestionScore;
  final int vehicleCount;
  final double lat;
  final double lng;
  final String? snapshotUrl;
  final String? level;
  final String? assignedAtIso;
  final String? enrouteAtIso;
  final String? onsceneAtIso;

  factory OfficerCase.fromJson(Map<String, dynamic> json) {
    final report = json['report'];
    final reportMap = report is Map ? Map<String, dynamic>.from(report) : <String, dynamic>{};
    return OfficerCase(
      assignmentId: '${json['assignmentId'] ?? ''}',
      status: '${json['status'] ?? ''}',
      nextStatus: json['nextStatus'] == null ? null : '${json['nextStatus']}',
      reportId: '${reportMap['id'] ?? ''}',
      location: '${reportMap['location'] ?? 'Villamonte'}',
      congestionScore: int.tryParse('${reportMap['congestionScore']}') ?? 0,
      vehicleCount: int.tryParse('${reportMap['vehicleCount']}') ?? 0,
      lat: double.tryParse('${reportMap['lat']}') ?? 0,
      lng: double.tryParse('${reportMap['lng']}') ?? 0,
      snapshotUrl: reportMap['snapshotUrl'] == null || '${reportMap['snapshotUrl']}'.isEmpty
          ? null
          : '${reportMap['snapshotUrl']}',
      level: reportMap['level'] == null || '${reportMap['level']}'.isEmpty ? null : '${reportMap['level']}',
      assignedAtIso: _blankToNull(json['assignedAtIso']),
      enrouteAtIso: _blankToNull(json['enrouteAtIso']),
      onsceneAtIso: _blankToNull(json['onsceneAtIso']),
    );
  }
}

class OfficerHistory {
  const OfficerHistory({
    required this.assignmentId,
    required this.reportId,
    required this.location,
    required this.assignedAtIso,
    required this.onsceneAtIso,
    required this.resolvedAtIso,
    required this.vehicleCount,
    required this.congestionScore,
    this.level,
    this.snapshotUrl,
  });

  final String assignmentId;
  final String reportId;
  final String location;
  final String? assignedAtIso;
  final String? onsceneAtIso;
  final String? resolvedAtIso;
  final int? vehicleCount;
  final int? congestionScore;
  final String? level;
  final String? snapshotUrl;

  factory OfficerHistory.fromJson(Map<String, dynamic> json) {
    int? number(Object? value) {
      if (value == null || '$value'.isEmpty) return null;
      return int.tryParse('$value');
    }

    String? stamp(Object? value) {
      final text = value == null ? '' : '$value';
      return text.isEmpty ? null : text;
    }

    return OfficerHistory(
      assignmentId: '${json['assignmentId'] ?? ''}',
      reportId: '${json['reportId'] ?? ''}',
      location: '${json['location'] ?? ''}',
      assignedAtIso: stamp(json['assignedAtIso']),
      onsceneAtIso: stamp(json['onsceneAtIso']),
      resolvedAtIso: stamp(json['resolvedAtIso']),
      vehicleCount: number(json['vehicleCount']),
      congestionScore: number(json['congestionScore']),
      level: json['level'] == null || '${json['level']}'.isEmpty ? null : '${json['level']}',
      snapshotUrl: json['snapshotUrl'] == null || '${json['snapshotUrl']}'.isEmpty ? null : '${json['snapshotUrl']}',
    );
  }
}

class OfficerSnapshot {
  const OfficerSnapshot({
    required this.radio,
    required this.name,
    required this.task,
  });

  final String radio;
  final String name;
  final OfficerCase? task;

  factory OfficerSnapshot.fromJson(Map<String, dynamic> json) {
    final officer = json['officer'];
    final officerMap = officer is Map ? Map<String, dynamic>.from(officer) : <String, dynamic>{};
    final task = json['task'];
    return OfficerSnapshot(
      radio: '${officerMap['radio'] ?? ''}',
      name: '${officerMap['fullName'] ?? officerMap['name'] ?? 'Officer'}',
      task: task is Map ? OfficerCase.fromJson(Map<String, dynamic>.from(task)) : null,
    );
  }
}

class OfficerApi {
  static const _baseKey = 'officer_base';
  static const _cookieKey = 'officer_cookie';

  String? _base;
  String? _cookie;

  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    _base = prefs.getString(_baseKey);
    _cookie = prefs.getString(_cookieKey);
    return _base != null && _base!.isNotEmpty && _cookie != null && _cookie!.isNotEmpty;
  }

  Future<String?> login(String username, String password) async {
    final body = jsonEncode({
      'action': 'login',
      'username': username.trim().toLowerCase(),
      'password': password,
    });
    final notes = <String>[];
    for (final base in [AppConfig.baseUrl, AppConfig.localBaseUrl, AppConfig.emulatorBaseUrl]) {
      final where = _hostLabel(base);
      try {
        final response = await _post(Uri.parse('$base/api/auth.php'), body).timeout(const Duration(seconds: 12));
        final decoded = _json(response.body);
        if (response.statusCode == 429) {
          return '$where: ${decoded['error'] ?? 'Too many failed attempts. Wait 10 minutes and try again.'}';
        }
        if (response.statusCode != 200 || decoded['ok'] != true) {
          notes.add('$where: ${decoded['error'] ?? 'Could not sign in.'}');
          continue;
        }
        final session = decoded['session'];
        final user = decoded['user'];
        final role = session is Map ? session['role'] : (user is Map ? user['role'] : null);
        if (role != 'field_officer') {
          return 'This login is for the officer phone. Use the phone username on the officer profile, not the desk account.';
        }
        final cookie = response.sessionId;
        if (cookie == null || cookie.isEmpty) {
          notes.add('$where answered, but did not start a session.');
          continue;
        }
        _base = base;
        _cookie = cookie;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_baseKey, base);
        await prefs.setString(_cookieKey, cookie);
        return null;
      } on TimeoutException {
        notes.add('$where did not answer.');
      } on SocketException {
        notes.add('$where is not reachable from this phone.');
      } on HttpException {
        notes.add('$where is not reachable from this phone.');
      } on http.ClientException {
        notes.add('$where is not reachable from this phone.');
      }
    }
    if (notes.isEmpty) {
      return 'Could not reach the desk. Check the connection and try again.';
    }
    return notes.join('\n');
  }

  Future<_DeskReply> _post(Uri uri, String body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final session = response.cookies.where((cookie) => cookie.name == 'PHPSESSID');
      return _DeskReply(response.statusCode, text, session.isEmpty ? null : session.first.value);
    } finally {
      client.close(force: true);
    }
  }

  Future<OfficerSnapshot> fetchTask() async {
    final response = await _send('GET', '/api/officer_task.php');
    return OfficerSnapshot.fromJson(_ok(response));
  }

  Future<List<OfficerHistory>> fetchHistory() async {
    final response = await _send('GET', '/api/officer_task.php?view=history');
    final decoded = _ok(response);
    if (!decoded.containsKey('history')) {
      throw Exception('History is not on this desk yet.');
    }
    final rows = decoded['history'];
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => OfficerHistory.fromJson(Map<String, dynamic>.from(row))).toList();
  }

  Future<OfficerSnapshot> advance(String status) async {
    final response = await _send('POST', '/api/officer_task.php', {'status': status});
    return OfficerSnapshot.fromJson(_ok(response));
  }

  Future<void> logout() async {
    final base = _base;
    final cookie = _cookie;
    _base = null;
    _cookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseKey);
    await prefs.remove(_cookieKey);
    if (base == null || cookie == null) return;
    try {
      await http
          .post(
            Uri.parse('$base/api/auth.php'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'PHPSESSID=$cookie',
            },
            body: jsonEncode({'action': 'logout'}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<http.Response> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final base = _base;
    final cookie = _cookie;
    if (base == null || cookie == null) throw AuthException();
    final headers = {
      'Accept': 'application/json',
      'Cookie': 'PHPSESSID=$cookie',
      if (body != null) 'Content-Type': 'application/json',
    };
    final uri = Uri.parse('$base$path');
    try {
      if (method == 'POST') {
        return await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 12));
      }
      return await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw Exception('The desk did not answer. Try again.');
    } on SocketException {
      throw Exception('Could not reach the desk. Check the connection and try again.');
    } on http.ClientException {
      throw Exception('Could not reach the desk. Check the connection and try again.');
    }
  }

  Map<String, dynamic> _ok(http.Response response) {
    final decoded = _json(response.body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthException();
    }
    if (response.statusCode != 200 || decoded['ok'] != true) {
      throw Exception('${decoded['error'] ?? 'The desk could not update this case.'}');
    }
    return decoded;
  }

  Map<String, dynamic> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  String _hostLabel(String base) {
    if (base == AppConfig.baseUrl) return 'Live desk';
    if (base == AppConfig.localBaseUrl) return 'Laptop desk';
    return 'Emulator desk';
  }
}

class _DeskReply {
  const _DeskReply(this.statusCode, this.body, this.sessionId);

  final int statusCode;
  final String body;
  final String? sessionId;
}
