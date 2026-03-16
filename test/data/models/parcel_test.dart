import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:smartfarm_field/data/models/parcel.dart';

void main() {
  group('Parcel', () {
    test('fromMap boundary string icin dogru parse eder', () {
      final Map<String, dynamic> inputMap = <String, dynamic>{
        'id': 'parcel-1',
        'name': 'Parsel A',
        'boundary': jsonEncode(
          <List<double>>[
            <double>[40.0, 29.0],
            <double>[40.1, 29.1],
          ],
        ),
      };
      final Parcel actualParsel = Parcel.fromMap(inputMap);
      expect(actualParsel.id, 'parcel-1');
      expect(actualParsel.name, 'Parsel A');
      expect(actualParsel.boundary.length, 2);
      expect(actualParsel.boundary.first.latitude, 40.0);
      expect(actualParsel.boundary.first.longitude, 29.0);
    });
    test('fromMap boundary list icin dogru parse eder', () {
      final Map<String, dynamic> inputMap = <String, dynamic>{
        'id': 'parcel-2',
        'name': 'Parsel B',
        'boundary': <Map<String, double>>[
          <String, double>{'lat': 41.0, 'lng': 30.0},
          <String, double>{'lat': 41.2, 'lng': 30.2},
        ],
      };
      final Parcel actualParsel = Parcel.fromMap(inputMap);
      expect(actualParsel.id, 'parcel-2');
      expect(actualParsel.name, 'Parsel B');
      expect(actualParsel.boundary.length, 2);
      expect(actualParsel.boundary[1].latitude, 41.2);
      expect(actualParsel.boundary[1].longitude, 30.2);
    });
    test('toMap boundary listesini json stringe donusturur', () {
      final Parcel inputParsel = Parcel(
        id: 'parcel-3',
        name: 'Parsel C',
        boundary: <LatLng>[
          const LatLng(39.9, 28.9),
          const LatLng(40.0, 29.0),
        ],
      );
      final Map<String, dynamic> actualMap = inputParsel.toMap();
      final List<dynamic> actualBoundary = jsonDecode(actualMap['boundary'] as String);
      expect(actualMap['id'], 'parcel-3');
      expect(actualMap['name'], 'Parsel C');
      expect(actualBoundary.length, 2);
      expect(actualBoundary[0][0], 39.9);
      expect(actualBoundary[0][1], 28.9);
    });
  });
}
