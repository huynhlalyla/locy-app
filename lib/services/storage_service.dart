import 'package:shared_preferences/shared_preferences.dart';
import '../models/place.dart';
import '../config/app_config.dart';
import 'database_service.dart';

class StorageService {
  final DatabaseService _databaseService = DatabaseService();

  Future<List<Place>> loadPlaces() async {
    try {
      return await _databaseService.getAllPlaces();
    } catch (e) {
      print('Error loading places: $e');
      return [];
    }
  }

  Future<List<Place>> getPlacesByType(PlaceType type) async {
    try {
      return await _databaseService.getPlacesByType(type);
    } catch (e) {
      print('Error loading places by type: $e');
      return [];
    }
  }

  Future<Place?> getPlaceById(String id) async {
    try {
      return await _databaseService.getPlaceById(id);
    } catch (e) {
      print('Error getting place by id: $e');
      return null;
    }
  }

  Future<bool> savePlace(Place place) async {
    try {
      await _databaseService.insertPlace(place);
      return true;
    } catch (e) {
      print('Error saving place: $e');
      return false;
    }
  }

  Future<bool> updatePlace(Place place) async {
    try {
      await _databaseService.updatePlace(place);
      return true;
    } catch (e) {
      print('Error updating place: $e');
      return false;
    }
  }

  Future<bool> deletePlace(String id) async {
    try {
      await _databaseService.deletePlace(id);
      return true;
    } catch (e) {
      print('Error deleting place: $e');
      return false;
    }
  }

  Future<List<Place>> searchPlaces(String query) async {
    try {
      return await _databaseService.searchPlaces(query);
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  Future<int> getPlaceCount() async {
    try {
      return await _databaseService.getPlaceCount();
    } catch (e) {
      print('Error getting place count: $e');
      return 0;
    }
  }

  Future<Map<PlaceType, int>> getPlaceCountByType() async {
    try {
      return await _databaseService.getPlaceCountByType();
    } catch (e) {
      print('Error getting place count by type: $e');
      return {};
    }
  }

  Future<void> clearAllPlaces() async {
    try {
      await _databaseService.clearAllPlaces();
    } catch (e) {
      print('Error clearing all places: $e');
    }
  }

  // App preferences
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConfig.keyFirstLaunch) ?? true;
  }

  Future<void> setFirstLaunchComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConfig.keyFirstLaunch, false);
  }

  Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.keyThemeMode) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.keyThemeMode, mode);
  }

  Future<void> debugStorage() async {
    try {
      final places = await loadPlaces();
      final count = await getPlaceCount();
      final countByType = await getPlaceCountByType();

      print('=== Storage Debug Info ===');
      print('Total places: $count');
      print('Places by type: $countByType');
      print('Places: ${places.length}');
      for (var place in places) {
        print('  - ${place.name} (${place.type.displayName})');
      }
      print('========================');
    } catch (e) {
      print('Error in debug storage: $e');
    }
  }
}
