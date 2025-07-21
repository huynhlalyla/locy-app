import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../config/app_config.dart';

class LocationUtils {
  // Tính khoảng cách giữa hai điểm (km)
  static double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  // Lấy địa chỉ từ tọa độ
  static Future<String?> getAddressFromCoordinates(
    double latitude, double longitude
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude, longitude
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return [
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.country,
        ].where((element) => element != null && element.isNotEmpty).join(', ');
      }
      return null;
    } catch (e) {
      print('Error getting address from coordinates: $e');
      return null;
    }
  }

  // Lấy tọa độ từ địa chỉ
  static Future<Map<String, double>?> getCoordinatesFromAddress(
    String address
  ) async {
    try {
      List<Location> locations = await locationFromAddress(address);

      if (locations.isNotEmpty) {
        final location = locations.first;
        return {
          'latitude': location.latitude,
          'longitude': location.longitude,
        };
      }
      return null;
    } catch (e) {
      print('Error getting coordinates from address: $e');
      return null;
    }
  }

  // Kiểm tra xem có ở trong phạm vi không
  static bool isWithinRadius(
    double centerLat, double centerLon,
    double pointLat, double pointLon,
    double radiusKm
  ) {
    double distance = calculateDistance(centerLat, centerLon, pointLat, pointLon);
    return distance <= radiusKm;
  }

  // Format tọa độ thành chuỗi đẹp
  static String formatCoordinates(double latitude, double longitude) {
    final String latDirection = latitude >= 0 ? 'N' : 'S';
    final String lonDirection = longitude >= 0 ? 'E' : 'W';

    return '${latitude.abs().toStringAsFixed(6)}°$latDirection, '
           '${longitude.abs().toStringAsFixed(6)}°$lonDirection';
  }

  // Tạo URL Google Maps
  static String generateGoogleMapsUrl(
    double latitude, double longitude, {
    String? label,
    double zoom = 15.0,
  }) {
    final String baseUrl = 'https://maps.google.com/maps';
    final String coords = '$latitude,$longitude';

    if (label != null) {
      return '$baseUrl?q=$coords($label)&z=${zoom.toInt()}';
    }
    return '$baseUrl?q=$coords&z=${zoom.toInt()}';
  }

  // Validate tọa độ
  static bool isValidCoordinate(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    return latitude >= -90 && latitude <= 90 &&
           longitude >= -180 && longitude <= 180;
  }

  // Lấy vị trí mặc định (Hanoi)
  static Map<String, double> getDefaultLocation() {
    return {
      'latitude': AppConfig.defaultLatitude,
      'longitude': AppConfig.defaultLongitude,
    };
  }

  // Tạo bounds cho map
  static Map<String, double> calculateBounds(List<Map<String, double>> locations) {
    if (locations.isEmpty) return getDefaultLocation();

    double minLat = locations.first['latitude']!;
    double maxLat = locations.first['latitude']!;
    double minLon = locations.first['longitude']!;
    double maxLon = locations.first['longitude']!;

    for (var location in locations) {
      final lat = location['latitude']!;
      final lon = location['longitude']!;

      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    return {
      'minLatitude': minLat,
      'maxLatitude': maxLat,
      'minLongitude': minLon,
      'maxLongitude': maxLon,
    };
  }
}
