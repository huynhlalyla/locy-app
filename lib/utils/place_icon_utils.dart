import 'package:flutter/material.dart';
import '../models/place.dart';

class PlaceIconUtils {
  // Lấy icon cho từng loại địa điểm
  static IconData getIcon(PlaceType type) {
    switch (type) {
      case PlaceType.restaurant:
        return Icons.restaurant;
      case PlaceType.school:
        return Icons.school;
      case PlaceType.cafe:
        return Icons.local_cafe;
      case PlaceType.tourist:
        return Icons.place;
      case PlaceType.supermarket:
        return Icons.local_grocery_store;
      case PlaceType.other:
        return Icons.location_on;
    }
  }

  // Lấy màu cho từng loại địa điểm
  static Color getColor(PlaceType type) {
    switch (type) {
      case PlaceType.restaurant:
        return Colors.orange;
      case PlaceType.school:
        return Colors.blue;
      case PlaceType.cafe:
        return Colors.brown;
      case PlaceType.tourist:
        return Colors.green;
      case PlaceType.supermarket:
        return Colors.purple;
      case PlaceType.other:
        return Colors.grey;
    }
  }

  // Lấy widget icon với màu
  static Widget getIconWidget(PlaceType type, {double size = 24.0}) {
    return Icon(
      getIcon(type),
      color: getColor(type),
      size: size,
    );
  }

  // Lấy widget container với icon và background
  static Widget getIconContainer(PlaceType type, {double size = 40.0}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: getColor(type).withOpacity(0.1),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Icon(
        getIcon(type),
        color: getColor(type),
        size: size * 0.6,
      ),
    );
  }

  // Lấy chip widget cho loại địa điểm
  static Widget getTypeChip(PlaceType type) {
    return Chip(
      avatar: Icon(
        getIcon(type),
        color: getColor(type),
        size: 18,
      ),
      label: Text(
        type.displayName,
        style: TextStyle(
          color: getColor(type),
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: getColor(type).withOpacity(0.1),
      side: BorderSide(
        color: getColor(type).withOpacity(0.3),
        width: 1,
      ),
    );
  }

  // Lấy danh sách tất cả các loại với icon
  static List<Widget> getAllTypeChips({
    PlaceType? selectedType,
    Function(PlaceType)? onTap,
  }) {
    return PlaceType.values.map((type) {
      final isSelected = selectedType == type;
      return GestureDetector(
        onTap: () => onTap?.call(type),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          child: Chip(
            avatar: Icon(
              getIcon(type),
              color: isSelected ? Colors.white : getColor(type),
              size: 18,
            ),
            label: Text(
              type.displayName,
              style: TextStyle(
                color: isSelected ? Colors.white : getColor(type),
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: isSelected
              ? getColor(type)
              : getColor(type).withOpacity(0.1),
            side: BorderSide(
              color: getColor(type).withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
      );
    }).toList();
  }
}
