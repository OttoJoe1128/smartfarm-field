import 'dart:convert';
import 'package:latlong2/latlong.dart';

class Parcel {
  final String id;
  final String name;
  final List<LatLng> boundary; // Poligon noktalari

  Parcel({
    required this.id,
    required this.name,
    required this.boundary,
  });

  // Map'ten olusturma (Veritabani veya API)
  factory Parcel.fromMap(Map<String, dynamic> map) {
    // boundary veritabaninda JSON string olarak tutulabilir
    // veya API'den [[lat, lng], [lat, lng]] formatinda gelebilir
    List<LatLng> points = [];
    
    if (map['boundary'] is String) {
      final List<dynamic> decoded = jsonDecode(map['boundary']);
      points = decoded.map((p) => LatLng(p[0], p[1])).toList();
    } else if (map['boundary'] is List) {
      points = (map['boundary'] as List).map((p) {
        if (p is List) return LatLng(p[0], p[1]); // [lat, lng]
        if (p is Map) return LatLng(p['lat'], p['lng']); // {lat: ..., lng: ...}
        return const LatLng(0, 0);
      }).toList();
    }

    return Parcel(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? 'Adsiz Parsel',
      boundary: points,
    );
  }

  // Veritabanina kaydetmek icin Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      // List<LatLng> -> List<List<double>> -> JSON String
      'boundary': jsonEncode(
        boundary.map((p) => [p.latitude, p.longitude]).toList(),
      ),
    };
  }
}
