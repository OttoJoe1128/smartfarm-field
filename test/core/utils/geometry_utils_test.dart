import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:smartfarm_field/core/utils/geometry_utils.dart';

void main() {
  group('GeometryUtils.isPointInPolygon', () {
    test('nokta poligon icindeyse true doner', () {
      final List<LatLng> inputPoligon = <LatLng>[
        const LatLng(0, 0),
        const LatLng(0, 10),
        const LatLng(10, 10),
        const LatLng(10, 0),
      ];
      final LatLng inputNokta = const LatLng(5, 5);
      final bool actualSonuc = GeometryUtils.isPointInPolygon(inputNokta, inputPoligon);
      const bool expectedSonuc = true;
      expect(actualSonuc, expectedSonuc);
    });
    test('nokta poligon disindaysa false doner', () {
      final List<LatLng> inputPoligon = <LatLng>[
        const LatLng(0, 0),
        const LatLng(0, 10),
        const LatLng(10, 10),
        const LatLng(10, 0),
      ];
      final LatLng inputNokta = const LatLng(15, 15);
      final bool actualSonuc = GeometryUtils.isPointInPolygon(inputNokta, inputPoligon);
      const bool expectedSonuc = false;
      expect(actualSonuc, expectedSonuc);
    });
    test('bos poligon verildiginde false doner', () {
      final List<LatLng> inputPoligon = <LatLng>[];
      final LatLng inputNokta = const LatLng(1, 1);
      final bool actualSonuc = GeometryUtils.isPointInPolygon(inputNokta, inputPoligon);
      const bool expectedSonuc = false;
      expect(actualSonuc, expectedSonuc);
    });
  });
}
