import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/place.dart';
import '../config/app_config.dart';

class DatabaseService {
  static Database? _database;
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), AppConfig.databaseName);

    return await openDatabase(
      path,
      version: AppConfig.databaseVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE places (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        note TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_places_type ON places(type)');
    await db.execute('CREATE INDEX idx_places_created_at ON places(created_at)');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add updated_at column if upgrading from version 1
      await db.execute('ALTER TABLE places ADD COLUMN updated_at INTEGER DEFAULT 0');
    }
  }

  Future<List<Place>> getAllPlaces() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'places',
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return Place.fromMap(maps[i]);
    });
  }

  Future<List<Place>> getPlacesByType(PlaceType type) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'places',
      where: 'type = ?',
      whereArgs: [type.value],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return Place.fromMap(maps[i]);
    });
  }

  Future<Place?> getPlaceById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'places',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Place.fromMap(maps.first);
    }
    return null;
  }

  Future<int> insertPlace(Place place) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final placeMap = place.toMap();
    placeMap['updated_at'] = now;

    return await db.insert('places', placeMap);
  }

  Future<int> updatePlace(Place place) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final placeMap = place.toMap();
    placeMap['updated_at'] = now;

    return await db.update(
      'places',
      placeMap,
      where: 'id = ?',
      whereArgs: [place.id],
    );
  }

  Future<int> deletePlace(String id) async {
    final db = await database;
    return await db.delete(
      'places',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Place>> searchPlaces(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'places',
      where: 'name LIKE ? OR note LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return Place.fromMap(maps[i]);
    });
  }

  Future<int> getPlaceCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM places');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<PlaceType, int>> getPlaceCountByType() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT type, COUNT(*) as count FROM places GROUP BY type'
    );

    Map<PlaceType, int> counts = {};
    for (var row in result) {
      final type = PlaceType.fromString(row['type'] as String);
      counts[type] = row['count'] as int;
    }

    return counts;
  }

  Future<void> clearAllPlaces() async {
    final db = await database;
    await db.delete('places');
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
