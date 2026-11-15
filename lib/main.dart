import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'road_route.dart';

/// Desk dark theme from the web (`theme.css`).
class BitcasColors {
  static const bg = Color(0xFF0A111F);
  static const surface = Color(0xFF111A2B);
  static const line = Color(0xFF1E2A40);
  static const text = Color(0xFFE6ECF5);
  static const muted = Color(0xFF8D9DB5);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFF87171);
  static const tab = Color(0xFF26365A);
}

const activeEmptyText = 'No active assignment';

/// The desk moved this case, so the button on screen is no longer the next step.
bool deskStepMovedOn(String message) {
  final text = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
  return text.contains('not next') || text.contains('No open task');
}

/// Minutes from [startIso] to [endIso]. Null when either stamp is missing.
String? formatFieldMinutes(String? startIso, String? endIso) {
  final start = DateTime.tryParse(startIso ?? '');
  final end = DateTime.tryParse(endIso ?? '');
  if (start == null || end == null) return null;
  final minutes = end.difference(start).inMinutes;
  if (minutes < 0) return null;
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

String formatResolvedWhen(String? iso) {
  final parsed = DateTime.tryParse(iso ?? '');
  if (parsed == null) return '—';
  final time = parsed.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour24 = time.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  return '${months[time.month - 1]} ${time.day}, $hour:$minute $suffix';
}

String congestionStatus({int? score, String? stored}) {
  final named = (stored ?? '').trim().toLowerCase();
  if (named == 'light' || named == 'low') return 'Light';
  if (named == 'moderate') return 'Moderate';
  if (named == 'heavy' || named == 'high' || named == 'severe') return 'Heavy';
  if (score == null) return '—';
  if (score >= 65) return 'Heavy';
  if (score >= 40) return 'Moderate';
  return 'Light';
}

String historyFacts(OfficerHistory row) {
  final vehicles = row.vehicleCount == null ? null : '${row.vehicleCount} vehicles';
  final status = congestionStatus(score: row.congestionScore, stored: row.level);
  final parts = [vehicles, status == '—' ? null : status].whereType<String>();
  if (parts.isEmpty) return '—';
  return parts.join(' · ');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfficerApp());
}

class BitcasMark extends StatelessWidget {
  const BitcasMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/bitcas-mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'BITCAS',
    );
  }
}

ThemeData bitcasTheme() {
  const scheme = ColorScheme.dark(
    surface: BitcasColors.bg,
    primary: BitcasColors.orange,
    onPrimary: Colors.white,
    error: BitcasColors.red,
    onSurface: BitcasColors.text,
  );
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: BitcasColors.bg,
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: BitcasColors.bg,
      foregroundColor: BitcasColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    useMaterial3: true,
  );
}

ButtonStyle deskPrimaryStyle() {
  return FilledButton.styleFrom(
    backgroundColor: BitcasColors.orange,
    foregroundColor: Colors.white,
    disabledBackgroundColor: const Color(0x73F59E0B),
    disabledForegroundColor: Colors.white,
    minimumSize: const Size.fromHeight(48),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

ButtonStyle deskOutlineStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: BitcasColors.text,
    minimumSize: const Size.fromHeight(48),
    side: const BorderSide(color: BitcasColors.line),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class OfficerApp extends StatefulWidget {
  const OfficerApp({super.key});

  @override
  State<OfficerApp> createState() => _OfficerAppState();
}

class _OfficerAppState extends State<OfficerApp> {
  final OfficerApi _api = OfficerApi();
  bool _ready = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final signedIn = await _api.load();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _signedIn = signedIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BITCAS Officer',
      theme: bitcasTheme(),
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator(color: BitcasColors.orange)))
          : _signedIn
              ? TaskScreen(
                  api: _api,
                  onSignedOut: () => setState(() => _signedIn = false),
                )
              : LoginScreen(
                  api: _api,
                  onSignedIn: () => setState(() => _signedIn = true),
                ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onSignedIn});

  final OfficerApi api;
  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.api.login(_username.text, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onSignedIn();
  }

  InputDecoration _field(String label) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: BitcasColors.line),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: BitcasColors.muted, fontSize: 12),
      filled: true,
      fillColor: BitcasColors.bg,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: BitcasColors.orange)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BitcasColors.bg,
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: BitcasColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: BitcasColors.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: BitcasMark(size: 72)),
                        const SizedBox(height: 12),
                        const Text('BITCAS', style: TextStyle(color: BitcasColors.text, fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text(
                          'The radio is the order to move. This phone shows the case you were assigned.',
                          style: TextStyle(color: BitcasColors.muted, height: 1.35),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _username,
                          autocorrect: false,
                          style: const TextStyle(color: BitcasColors.text),
                          textInputAction: TextInputAction.next,
                          decoration: _field('Username'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          style: const TextStyle(color: BitcasColors.text),
                          onSubmitted: (_) => _busy ? null : _submit(),
                          decoration: _field('Password'),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: BitcasColors.red, fontSize: 12)),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          style: deskPrimaryStyle(),
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy ? 'Signing in…' : 'Sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key, required this.api, required this.onSignedOut});

  final OfficerApi api;
  final VoidCallback onSignedOut;

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 10);

  OfficerSnapshot? _snapshot;
  List<OfficerHistory> _history = const [];
  String? _error;
  String? _historyError;
  bool _loading = true;
  bool _saving = false;
  bool _refreshing = false;
  int _tab = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadHistory();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncPoll() {
    final open = _snapshot?.task != null;
    if (!open) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      if (!mounted || _saving) return;
      _load(quiet: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _loadHistory();
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (quiet && _saving) return;
    if (_refreshing) return;
    _refreshing = true;
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    try {
      final snapshot = await widget.api.fetchTask();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } on AuthException {
      await widget.api.logout();
      if (mounted) widget.onSignedOut();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    } finally {
      _refreshing = false;
      if (mounted) _syncPoll();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await widget.api.fetchHistory();
      if (!mounted) return;
      setState(() {
        _history = rows;
        _historyError = null;
      });
    } on AuthException {
      await widget.api.logout();
      if (mounted) widget.onSignedOut();
    } catch (error) {
      if (!mounted) return;
      setState(() => _historyError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _advance(String status) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final snapshot = await widget.api.advance(status);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _saving = false;
      });
      _syncPoll();
      if (snapshot.task == null) _loadHistory();
    } on AuthException {
      await widget.api.logout();
      if (mounted) widget.onSignedOut();
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      if (deskStepMovedOn(message)) {
        setState(() => _saving = false);
        await _load();
        return;
      }
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  Future<void> _pressStep(OfficerCase task) async {
    final next = task.nextStatus;
    if (next == null || _saving) return;
    if (next == 'Resolved') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xF0111A2B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Resolve this case?', style: TextStyle(color: BitcasColors.text)),
          content: const Text(
            'This records the case as cleared. It leaves the map and stays in History.',
            style: TextStyle(color: BitcasColors.muted),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: deskPrimaryStyle(),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resolve'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _advance(next);
  }

  void _showDetails(OfficerCase task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailsSheet(task: task),
    );
  }

  Future<void> _signOut() async {
    await widget.api.logout();
    if (mounted) widget.onSignedOut();
  }

  Widget _tabButton(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? BitcasColors.tab : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? BitcasColors.text : BitcasColors.muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeBody(OfficerCase? task) {
    return RefreshIndicator(
      color: BitcasColors.orange,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: BitcasColors.red, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          if (!_loading && task == null)
            const Padding(
              padding: EdgeInsets.only(top: 72),
              child: Column(
                children: [
                  Text(activeEmptyText, textAlign: TextAlign.center, style: TextStyle(color: BitcasColors.text, fontSize: 20, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Text('Stand by on the radio.', textAlign: TextAlign.center, style: TextStyle(color: BitcasColors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyBody() {
    return RefreshIndicator(
      color: BitcasColors.orange,
      onRefresh: _loadHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_historyError != null) ...[
            Text(_historyError!, style: const TextStyle(color: BitcasColors.red, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          if (_history.isEmpty && _historyError == null)
            const Padding(
              padding: EdgeInsets.only(top: 72),
              child: Text('No resolved cases yet.', textAlign: TextAlign.center, style: TextStyle(color: BitcasColors.text, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ..._history.map(_historyCard),
        ],
      ),
    );
  }

  Widget _historyCard(OfficerHistory row) {
    final place = row.location.isEmpty ? row.reportId : row.location;
    final response = formatFieldMinutes(row.assignedAtIso, row.onsceneAtIso) ?? '—';
    final total = formatFieldMinutes(row.assignedAtIso, row.resolvedAtIso) ?? '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC111A2B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.snapshotUrl != null)
                Image.network(
                  row.snapshotUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 72,
                    child: Center(child: Text('Snapshot unavailable', style: TextStyle(color: BitcasColors.muted))),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(place, style: const TextStyle(color: BitcasColors.text, fontWeight: FontWeight.w600, fontSize: 15))),
                        const SizedBox(width: 8),
                        Text(formatResolvedWhen(row.resolvedAtIso), style: const TextStyle(color: BitcasColors.muted, fontSize: 12)),
                      ],
                    ),
                    if (row.location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(row.reportId, style: const TextStyle(color: BitcasColors.muted, fontSize: 12)),
                    ],
                    const SizedBox(height: 8),
                    Text('Response $response · Total $total', style: const TextStyle(color: BitcasColors.text, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(historyFacts(row), style: const TextStyle(color: BitcasColors.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final task = snapshot?.task;
    final radio = snapshot == null || snapshot.radio.isEmpty ? 'Officer' : snapshot.radio;
    if (_tab == 0 && task != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: ActiveMapPage(
          task: task,
          radio: radio,
          saving: _saving,
          error: _error,
          onSignOut: _signOut,
          onShowHistory: () => setState(() => _tab = 1),
          onDetails: () => _showDetails(task),
          onStep: () => _pressStep(task),
        ),
      );
    }
    return Scaffold(
      backgroundColor: BitcasColors.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const BitcasMark(size: 32),
            const SizedBox(width: 10),
            Flexible(child: Text(radio, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          ],
        ),
        actions: [
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout), tooltip: 'Sign out', color: BitcasColors.muted),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(color: BitcasColors.orange, backgroundColor: BitcasColors.line, minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(children: [_tabButton('Active', 0), _tabButton('History', 1)]),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [_activeBody(task), _historyBody()],
            ),
          ),
        ],
      ),
    );
  }
}

class ActiveMapPage extends StatefulWidget {
  const ActiveMapPage({
    super.key,
    required this.task,
    required this.radio,
    required this.saving,
    required this.error,
    required this.onSignOut,
    required this.onShowHistory,
    required this.onDetails,
    required this.onStep,
  });

  final OfficerCase task;
  final String radio;
  final bool saving;
  final String? error;
  final VoidCallback onSignOut;
  final VoidCallback onShowHistory;
  final VoidCallback onDetails;
  final VoidCallback onStep;

  @override
  State<ActiveMapPage> createState() => _ActiveMapPageState();
}

class _ActiveMapPageState extends State<ActiveMapPage> {
  final MapController _map = MapController();
  final Distance _distance = const Distance();
  StreamSubscription<Position>? _positions;
  LatLng? _here;
  LatLng? _routeOrigin;
  RoadRoute? _route;
  String? _locationNote;
  bool _fitted = false;
  int _routeToken = 0;

  @override
  void initState() {
    super.initState();
    _beginFollow();
  }

  @override
  void didUpdateWidget(ActiveMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.assignmentId != widget.task.assignmentId) {
      _route = null;
      _routeOrigin = null;
      _fitted = false;
      _beginFollow();
    }
  }

  @override
  void dispose() {
    _positions?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _beginFollow() async {
    await _positions?.cancel();
    _positions = null;
    final id = widget.task.assignmentId;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted || widget.task.assignmentId != id) return;
      if (!enabled) {
        setState(() => _locationNote = 'Location is off');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted || widget.task.assignmentId != id) return;
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationNote = 'Location permission is needed for the route');
        return;
      }
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted || widget.task.assignmentId != id) return;
      _applyPosition(first);
      _positions = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
      ).listen(_applyPosition);
    } catch (_) {
      if (!mounted || widget.task.assignmentId != id) return;
      setState(() => _locationNote = 'Location is unavailable');
    }
  }

  void _applyPosition(Position position) {
    final here = LatLng(position.latitude, position.longitude);
    final moved = _routeOrigin == null ? double.infinity : _distance(_routeOrigin!, here);
    setState(() {
      _here = here;
      if (_route != null) _locationNote = null;
    });
    if (moved > 40) _loadRoute(here);
  }

  Future<void> _loadRoute(LatLng here) async {
    final token = ++_routeToken;
    final task = widget.task;
    _routeOrigin = here;
    try {
      final route = await fetchDrivingRoute(here, LatLng(task.lat, task.lng));
      if (!mounted || token != _routeToken) return;
      setState(() {
        _route = route;
        _locationNote = route == null ? 'Road route is unavailable' : null;
      });
      if (route != null && !_fitted) {
        _fitted = true;
        final points = [...route.points, here, LatLng(task.lat, task.lng)];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || token != _routeToken) return;
          _map.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.fromLTRB(48, 168, 48, 250),
          ));
        });
      }
    } catch (_) {
      if (!mounted || token != _routeToken) return;
      setState(() => _locationNote = 'Road route is unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final here = _here;
    final route = _route;
    final trip = route == null ? (_locationNote ?? 'Finding the road route…') : formatTrip(route.distanceMeters, route.durationSeconds);
    final action = _stepLabel(task.nextStatus);
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: LatLng(task.lat, task.lng),
            initialZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.bacolodlife.bitcas.bitcas_officer',
            ),
            if (route != null)
              PolylineLayer(
                polylines: [
                  Polyline(points: route.points, color: const Color(0xFF5B9BFF), strokeWidth: 5),
                ],
              ),
            MarkerLayer(
              markers: [
                if (here != null)
                  Marker(
                    point: here,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B9BFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
                      ),
                    ),
                  ),
                Marker(
                  point: LatLng(task.lat, task.lng),
                  width: 42,
                  height: 42,
                  child: const Icon(Icons.location_on, color: BitcasColors.orange, size: 42),
                ),
              ],
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                _glassBar(
                  child: Row(
                    children: [
                      const BitcasMark(size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(widget.radio, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BitcasColors.text, fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(onPressed: widget.onSignOut, icon: const Icon(Icons.logout), tooltip: 'Sign out', color: BitcasColors.muted),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _glassBar(
                  child: Row(
                    children: [
                      Expanded(child: _pill('Active', true, null)),
                      Expanded(child: _pill('History', false, widget.onShowHistory)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _glassBar(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.location, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BitcasColors.text, fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(task.status, style: const TextStyle(color: BitcasColors.orange, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 8),
                  _glassBar(child: Text(widget.error!, style: const TextStyle(color: BitcasColors.red, fontSize: 13))),
                ],
                const Spacer(),
                _glassBar(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(trip, style: const TextStyle(color: BitcasColors.text, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: deskOutlineStyle(),
                              onPressed: widget.onDetails,
                              child: const Text('Details'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              style: deskPrimaryStyle(),
                              onPressed: widget.saving || action == null ? null : widget.onStep,
                              child: Text(widget.saving ? 'Saving…' : (action ?? 'Up to date')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text('© OpenStreetMap', style: TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _glassBar({required Widget child}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xC0111A2B),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: child),
      ),
    ),
  );
}

Widget _pill(String label, bool selected, VoidCallback? onTap) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xCCFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF0A111F) : BitcasColors.muted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
  );
}

String? _stepLabel(String? next) {
  if (next == 'En route') return 'Mark en route';
  if (next == 'On scene') return 'Mark on scene';
  if (next == 'Resolved') return 'Resolve';
  return null;
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({required this.task});

  final OfficerCase task;

  @override
  Widget build(BuildContext context) {
    final status = congestionStatus(score: task.congestionScore, stored: task.level);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xF0111A2B)),
            child: SafeArea(
              top: false,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(task.location, style: const TextStyle(color: BitcasColors.text, fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(task.reportId, style: const TextStyle(color: BitcasColors.muted)),
                  const SizedBox(height: 14),
                  if (task.snapshotUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        task.snapshotUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 80,
                          child: Center(child: Text('Snapshot unavailable', style: TextStyle(color: BitcasColors.muted))),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _detailRow('Status', status),
                  _detailRow('Vehicles', '${task.vehicleCount}'),
                  _detailRow('Step', task.status),
                  _detailRow('Assigned', formatResolvedWhen(task.assignedAtIso)),
                  _detailRow('En route', formatResolvedWhen(task.enrouteAtIso)),
                  _detailRow('On scene', formatResolvedWhen(task.onsceneAtIso)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: BitcasColors.muted))),
        Text(value, style: const TextStyle(color: BitcasColors.text, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

