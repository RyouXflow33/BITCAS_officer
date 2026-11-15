import 'package:bitcas_officer/api.dart';
import 'package:bitcas_officer/main.dart';
import 'package:bitcas_officer/road_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login shows the mark and the radio order', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(api: OfficerApi(), onSignedIn: () {}),
    ));

    expect(find.byType(BitcasMark), findsOneWidget);
    expect(
      find.text('The radio is the order to move. This phone shows the case you were assigned.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('Active is empty until the desk assigns a case', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TaskScreen(api: QuietApi(), onSignedOut: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bravo-01'), findsOneWidget);
    expect(find.text(activeEmptyText), findsOneWidget);
    expect(find.byType(BitcasMark), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No resolved cases yet.'), findsOneWidget);
    expect(find.text('Villamonte Street Intersection'), findsNothing);
  });

  test('A step the desk already took is reloaded instead of left on the old button', () {
    expect(deskStepMovedOn('That step is not next. Refresh the case.'), isTrue);
    expect(deskStepMovedOn('Exception: No open task. Stand by on the radio.'), isTrue);
    expect(deskStepMovedOn('Could not reach the desk. Check the connection and try again.'), isFalse);
  });

  test('History times run from assigned to on scene, then to resolved', () {
    expect(formatFieldMinutes('2026-11-15T12:00:00Z', '2026-11-15T12:11:00Z'), '11 min');
    expect(formatFieldMinutes('2026-11-15T12:00:00Z', '2026-11-15T12:00:20Z'), '<1 min');
    expect(formatFieldMinutes('2026-11-15T12:00:00Z', '2026-11-15T13:30:00Z'), '1 h 30 min');
    expect(formatFieldMinutes('2026-11-15T12:00:00Z', null), isNull);
    expect(congestionStatus(score: 39), 'Light');
    expect(congestionStatus(score: 40), 'Moderate');
    expect(congestionStatus(score: 64), 'Moderate');
    expect(congestionStatus(score: 65), 'Heavy');
    expect(congestionStatus(stored: 'High'), 'Heavy');
    expect(formatTrip(3400, 660), '3.4 km · 11 min');
    final route = roadRouteFromOsrm({
      'routes': [
        {
          'distance': 1200,
          'duration': 180,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [122.96, 10.66],
              [122.967, 10.664],
            ],
          },
        },
      ],
    });
    expect(route, isNotNull);
    expect(route!.points.first.latitude, closeTo(10.66, 0.0001));
    expect(route.points.first.longitude, closeTo(122.96, 0.0001));
    expect(roadRouteFromOsrm({'routes': []}), isNull);
    expect(
      historyFacts(const OfficerHistory(
        assignmentId: 'DSP-1',
        reportId: 'RPT-1',
        location: 'Villamonte',
        assignedAtIso: '2026-11-15T12:00:00Z',
        onsceneAtIso: '2026-11-15T12:11:00Z',
        resolvedAtIso: '2026-11-15T12:24:00Z',
        vehicleCount: 6,
        congestionScore: 65,
      )),
      '6 vehicles · Heavy',
    );
  });
}

class QuietApi extends OfficerApi {
  @override
  Future<OfficerSnapshot> fetchTask() async {
    return const OfficerSnapshot(radio: 'Bravo-01', name: 'Juan Tamad', task: null);
  }

  @override
  Future<List<OfficerHistory>> fetchHistory() async => const [];
}
