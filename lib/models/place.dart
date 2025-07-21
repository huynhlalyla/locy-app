import 'dart:convert';

enum PlaceType {
  restaurant('Quán ăn', 'restaurant'),
  school('Trường học', 'school'),
  cafe('Quán cà phê', 'cafe'),
  tourist('Địa điểm du lịch', 'tourist'),
  supermarket('Siêu thị', 'supermarket'),
  other('Khác', 'other');

  const PlaceType(this.displayName, this.value);
  final String displayName;
  final String value;

  static PlaceType fromString(String value) {
    return PlaceType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => PlaceType.other,
    );
  }
}

class Place {
  final String id;
  final String name;
  final PlaceType type;
  final String? note;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  Place({
    required this.id,
    required this.name,
    required this.type,
    this.note,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.value,
      'note': note,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: map['id'] as String,
      name: map['name'] as String,
      type: PlaceType.fromString(map['type'] as String),
      note: map['note'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at'] as int? ?? map['created_at'] as int,
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory Place.fromJson(String source) {
    try {
      return Place.fromMap(json.decode(source));
    } catch (e) {
      print('Error parsing Place from JSON: $e');
      return Place(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Lỗi đọc JSON',
        type: PlaceType.other,
        note: null,
        latitude: 0.0,
        longitude: 0.0,
        createdAt: DateTime.now(),
      );
    }
  }

  @override
  String toString() {
    return 'Place(id: $id, name: $name, type: ${type.displayName}, note: $note, lat: $latitude, lng: $longitude, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  Place copyWith({
    String? id,
    String? name,
    PlaceType? type,
    String? note,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      note: note ?? this.note,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
