import 'package:latlong2/latlong.dart';

void main() {
  final polygon = [
    LatLng(0, 0),
    LatLng(0, 10),
    LatLng(10, 10),
    LatLng(10, 0),
  ];

  final point = LatLng(5, 5);

  bool isInside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
        (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
      isInside = !isInside;
    }
  }
  print('isInside: $isInside');
}
