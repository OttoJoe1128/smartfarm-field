import 'package:latlong2/latlong.dart';

class GeometryUtils {
  /// Bir noktanin (point) bir poligon (vertices) icinde olup olmadigini kontrol eder.
  /// Ray-Casting algoritmasi kullanir.
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    
    bool isInside = false;
    int i = 0;
    int j = polygon.length - 1;

    for (i = 0; i < polygon.length; j = i++) {
      if (((polygon[i].longitude > point.longitude) != 
          (polygon[j].longitude > point.longitude)) &&
          (point.latitude < 
              (polygon[j].latitude - polygon[i].latitude) * 
              (point.longitude - polygon[i].longitude) / 
              (polygon[j].longitude - polygon[i].longitude) + 
              polygon[i].latitude)) {
        isInside = !isInside;
      }
    }

    return isInside;
  }
}
