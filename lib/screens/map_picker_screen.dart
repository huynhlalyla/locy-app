import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'add_place_screen.dart';

// Model cho kết quả tìm kiếm thống nhất
class SearchResult {
  final String displayName;
  final String description;
  final double latitude;
  final double longitude;
  final String source; // 'geocoding', 'nominatim', 'google_places'
  final String? placeId;
  final List<String> types;

  SearchResult({
    required this.displayName,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.source,
    this.placeId,
    this.types = const [],
  });
}

class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const MapPickerScreen({Key? key, this.initialLatitude, this.initialLongitude})
    : super(key: key);

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen>
    with WidgetsBindingObserver {
  GoogleMapController? _controller;
  Position? _currentPosition;
  LatLng? _selectedPosition;
  bool _isLoadingLocation = true;
  bool _isSearching = false;
  Set<Marker> _markers = {};

  final TextEditingController _searchController = TextEditingController();
  List<SearchResult> _searchResults = [];
  bool _showSearchResults = false;

  // Tối ưu tìm kiếm với debounce
  Timer? _searchDebounce;
  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Xử lý dữ liệu từ Google Maps khi ứng dụng được mở lại
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForSharedLocation();
    }
  }

  Future<void> _checkForSharedLocation() async {
    // Kiểm tra xem có dữ liệu vị trí được chia sẻ từ Google Maps không
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        final String text = data.text!;
        // Kiểm tra nếu clipboard chứa tọa độ (format: "latitude,longitude")
        final RegExp coordRegex = RegExp(r'^-?\d+\.?\d*,-?\d+\.?\d*$');
        if (coordRegex.hasMatch(text)) {
          final List<String> coords = text.split(',');
          if (coords.length == 2) {
            final double? lat = double.tryParse(coords[0]);
            final double? lng = double.tryParse(coords[1]);
            if (lat != null && lng != null) {
              _setSelectedPosition(LatLng(lat, lng));
            }
          }
        }
      }
    } catch (e) {
      // Ignore clipboard errors
    }
  }

  Future<void> _initializeLocation() async {
    // Nếu có tọa độ ban đầu (từ share), sử dụng nó
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      setState(() {
        _selectedPosition = LatLng(
          widget.initialLatitude!,
          widget.initialLongitude!,
        );
        _isLoadingLocation = false;
      });
      _updateMarkers();
      return;
    }

    // Ngược lại, lấy vị trí hiện tại
    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationPermissionDialog();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationPermissionDialog();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _selectedPosition = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });

      _updateMarkers();
      _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
      });
      _showErrorDialog('Không thể lấy vị trí hiện tại: ${e.toString()}');
    }
  }

  void _updateMarkers() {
    _markers.clear();

    if (_currentPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          infoWindow: const InfoWindow(
            title: 'Vị trí hiện tại',
            snippet: 'Đây là vị trí hiện tại của bạn',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    if (_selectedPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: _selectedPosition!,
          infoWindow: const InfoWindow(
            title: 'Vị trí đã chọn',
            snippet: 'Vị trí bạn muốn lưu',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
  }

  void _setSelectedPosition(LatLng position) {
    setState(() {
      _selectedPosition = position;
      _updateMarkers();
    });

    _controller?.animateCamera(CameraUpdate.newLatLng(position));
  }

  void _onMapTap(LatLng position) {
    _setSelectedPosition(position);
    setState(() {
      _showSearchResults = false;
    });
  }

  Future<void> _searchLocation(String query) async {
    // Debounce để tránh gọi API quá nhiều
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      await _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    // Kiểm tra nếu query rỗng hoặc giống query trước
    if (query.isEmpty || query.trim().length < 2) {
      setState(() {
        _searchResults.clear();
        _showSearchResults = false;
      });
      return;
    }

    // Tránh tìm kiếm lặp lại
    if (query.trim() == _lastSearchQuery) {
      return;
    }

    _lastSearchQuery = query.trim();

    setState(() {
      _isSearching = true;
    });

    try {
      List<SearchResult> allResults = [];

      // 1. Tìm kiếm với Geocoding API (Flutter built-in)
      List<SearchResult> geocodingResults = await _searchWithGeocoding(query);
      allResults.addAll(geocodingResults);

      // 2. Tìm kiếm với Nominatim API (OpenStreetMap)
      List<SearchResult> nominatimResults = await _searchWithNominatim(query);
      allResults.addAll(nominatimResults);

      // Loại bỏ kết quả trùng lặp dựa trên khoảng cách
      List<SearchResult> uniqueResults = _removeDuplicateResults(allResults);

      // Sắp xếp kết quả theo mức độ liên quan
      uniqueResults = _sortResultsByRelevance(uniqueResults, query);

      setState(() {
        _searchResults = uniqueResults.take(10).toList(); // Giới hạn 10 kết quả
        _showSearchResults = uniqueResults.isNotEmpty;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchResults.clear();
        _showSearchResults = false;
        _isSearching = false;
      });
      print('Search error: $e');
    }
  }

  // Tìm kiếm với Geocoding API
  Future<List<SearchResult>> _searchWithGeocoding(String query) async {
    try {
      List<Location> locations = await locationFromAddress(query);
      List<SearchResult> results = [];

      for (var location in locations.take(3)) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            results.add(
              SearchResult(
                displayName: _getPlacemarkDisplayName(placemark),
                description: _getPlacemarkDescription(placemark),
                latitude: location.latitude,
                longitude: location.longitude,
                source: 'geocoding',
              ),
            );
          }
        } catch (e) {
          // Nếu không lấy được chi tiết, tạo kết quả cơ bản
          results.add(
            SearchResult(
              displayName: query,
              description: 'Địa điểm tìm được',
              latitude: location.latitude,
              longitude: location.longitude,
              source: 'geocoding',
            ),
          );
        }
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  // Tìm kiếm với Nominatim API (OpenStreetMap)
  Future<List<SearchResult>> _searchWithNominatim(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5&addressdetails=1&countrycodes=vn&extratags=1&namedetails=1',
      );

      final response = await http
          .get(url, headers: {'User-Agent': 'LOCY Mobile App/1.0'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<SearchResult> results = [];

        for (var item in data) {
          try {
            final lat = double.parse(item['lat'].toString());
            final lon = double.parse(item['lon'].toString());

            // Lấy tên địa điểm thông minh hơn
            String displayName = _extractBestDisplayName(item, query);

            // Tạo mô tả ngắn gọn hơn
            final address = item['address'] ?? {};
            String description = _buildNominatimDescription(address);

            results.add(
              SearchResult(
                displayName: displayName,
                description: description,
                latitude: lat,
                longitude: lon,
                source: 'nominatim',
                types: [
                  item['type']?.toString() ?? '',
                  item['class']?.toString() ?? '',
                ].where((s) => s.isNotEmpty).toList(),
              ),
            );
          } catch (e) {
            continue;
          }
        }
        return results;
      }
    } catch (e) {
      print('Nominatim search error: $e');
    }
    return [];
  }

  // Helper methods
  String _getPlacemarkDisplayName(Placemark placemark) {
    if (placemark.name != null && placemark.name!.isNotEmpty) {
      return placemark.name!;
    }
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      return placemark.street!;
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      return placemark.locality!;
    }
    return 'Địa điểm';
  }

  String _getPlacemarkDescription(Placemark placemark) {
    List<String> parts = [];
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      parts.add(placemark.street!);
    }
    if (placemark.subLocality != null && placemark.subLocality!.isNotEmpty) {
      parts.add(placemark.subLocality!);
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      parts.add(placemark.locality!);
    }
    if (placemark.administrativeArea != null &&
        placemark.administrativeArea!.isNotEmpty) {
      parts.add(placemark.administrativeArea!);
    }
    return parts.isNotEmpty ? parts.join(', ') : 'Việt Nam';
  }

  // Lấy tên hiển thị tốt nhất từ dữ liệu Nominatim
  String _extractBestDisplayName(Map<String, dynamic> item, String query) {
    // Ưu tiên 1: Kiểm tra namedetails nếu có
    final nameDetails = item['namedetails'] as Map<String, dynamic>?;
    if (nameDetails != null) {
      // Ưu tiên tên tiếng Việt
      if (nameDetails['name:vi'] != null &&
          nameDetails['name:vi'].toString().isNotEmpty) {
        return nameDetails['name:vi'].toString();
      }
      // Sau đó là tên chính
      if (nameDetails['name'] != null &&
          nameDetails['name'].toString().isNotEmpty) {
        String name = nameDetails['name'].toString();
        if (!_isPlusCode(name)) {
          return name;
        }
      }
    }

    // Ưu tiên 2: Kiểm tra address components
    final address = item['address'] as Map<String, dynamic>?;
    if (address != null) {
      // Ưu tiên các POI (points of interest)
      final poiFields = ['shop', 'amenity', 'leisure', 'tourism', 'building'];
      for (String field in poiFields) {
        if (address[field] != null && address[field].toString().isNotEmpty) {
          String value = address[field].toString();
          if (!_isPlusCode(value) &&
              value.toLowerCase().contains(query.toLowerCase())) {
            return value;
          }
        }
      }

      // Kiểm tra các tên địa điểm khác
      final nameFields = [
        'house_name',
        'building_name',
        'commercial',
        'retail',
      ];
      for (String field in nameFields) {
        if (address[field] != null && address[field].toString().isNotEmpty) {
          String value = address[field].toString();
          if (!_isPlusCode(value)) {
            return value;
          }
        }
      }
    }

    // Ưu tiên 3: Parse display_name thông minh
    final displayName = item['display_name']?.toString() ?? '';
    if (displayName.isNotEmpty) {
      final parts = displayName.split(', ');

      // Tìm phần không phải Plus Code và có liên quan đến query
      for (String part in parts) {
        part = part.trim();
        if (!_isPlusCode(part) && part.length > 1) {
          // Nếu part chứa từ khóa tìm kiếm, ưu tiên nó
          if (part.toLowerCase().contains(query.toLowerCase())) {
            return part;
          }
        }
      }

      // Nếu không tìm thấy, lấy phần đầu tiên không phải Plus Code
      for (String part in parts) {
        part = part.trim();
        if (!_isPlusCode(part) && part.length > 1) {
          return part;
        }
      }
    }

    // Fallback: Dùng type và class
    final type = item['type']?.toString() ?? '';
    final category = item['class']?.toString() ?? '';

    if (type.isNotEmpty && category.isNotEmpty) {
      return '$type ($category)';
    } else if (type.isNotEmpty) {
      return type;
    } else if (category.isNotEmpty) {
      return category;
    }

    // Cuối cùng: Dùng query gốc nếu không có gì khác
    return query;
  }

  // Kiểm tra xem một chuỗi có phải là Plus Code không
  bool _isPlusCode(String text) {
    // Plus Code pattern: 4-6 ký tự + dấu "+" + 2-3 ký tự
    final plusCodeRegex = RegExp(
      r'^[23456789CFGHJMPQRVWX]{4,6}\+[23456789CFGHJMPQRVWX]{2,3}$',
    );
    return plusCodeRegex.hasMatch(text.trim());
  }

  String _buildNominatimDescription(Map<String, dynamic> address) {
    List<String> parts = [];

    // Thêm các thành phần địa chỉ theo thứ tự ưu tiên
    final addressParts = [
      'house_number', // Số nhà
      'road', // Đường
      'suburb', // Phường/xã
      'neighbourhood', // Khu phố
      'quarter', // Quận nhỏ
      'city_district', // Quận/huyện
      'city', // Thành phố
      'town', // Thị trấn
      'village', // Làng
      'county', // Huyện
      'state', // Tỉnh/bang
      'province', // Tỉnh
    ];

    // Kết hợp số nhà và đường nếu có
    String roadInfo = '';
    if (address['house_number'] != null && address['road'] != null) {
      roadInfo = '${address['house_number']} ${address['road']}';
      parts.add(roadInfo);
      // Bỏ qua road trong vòng lặp
      addressParts.remove('house_number');
      addressParts.remove('road');
    } else if (address['road'] != null) {
      parts.add(address['road'].toString());
      addressParts.remove('road');
    }

    for (String key in addressParts) {
      if (address[key] != null && address[key].toString().isNotEmpty) {
        String value = address[key].toString();
        // Không thêm nếu đã có trong roadInfo
        if (roadInfo.isEmpty || !roadInfo.contains(value)) {
          parts.add(value);
        }
      }
    }

    // Nếu không có thông tin địa chỉ, thử lấy từ các trường khác
    if (parts.isEmpty) {
      final fallbackFields = ['postcode', 'country'];
      for (String key in fallbackFields) {
        if (address[key] != null && address[key].toString().isNotEmpty) {
          parts.add(address[key].toString());
        }
      }
    }

    return parts.isNotEmpty ? parts.join(', ') : 'Việt Nam';
  }

  // Loại bỏ kết quả trùng lặp dựa trên khoảng cách
  List<SearchResult> _removeDuplicateResults(List<SearchResult> results) {
    List<SearchResult> unique = [];
    const double threshold = 0.001; // Khoảng cách tối thiểu (khoảng 100m)

    for (var result in results) {
      bool isDuplicate = false;
      for (var existing in unique) {
        double distance = _calculateDistance(
          result.latitude,
          result.longitude,
          existing.latitude,
          existing.longitude,
        );
        if (distance < threshold) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        unique.add(result);
      }
    }
    return unique;
  }

  // Sắp xếp kết quả theo mức độ liên quan
  List<SearchResult> _sortResultsByRelevance(
    List<SearchResult> results,
    String query,
  ) {
    results.sort((a, b) {
      // Tính điểm liên quan cho mỗi kết quả
      int scoreA = _calculateRelevanceScore(a, query);
      int scoreB = _calculateRelevanceScore(b, query);

      // Sắp xếp theo điểm (cao nhất trước)
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }

      // Nếu điểm bằng nhau, ưu tiên theo nguồn
      const sourceOrder = {'geocoding': 0, 'nominatim': 1, 'google_places': 2};
      int aOrder = sourceOrder[a.source] ?? 999;
      int bOrder = sourceOrder[b.source] ?? 999;

      return aOrder.compareTo(bOrder);
    });

    return results;
  }

  // Tính điểm liên quan giữa kết quả và từ khóa tìm kiếm
  int _calculateRelevanceScore(SearchResult result, String query) {
    int score = 0;
    String lowerQuery = query.toLowerCase();
    String lowerName = result.displayName.toLowerCase();
    String lowerDesc = result.description.toLowerCase();

    // Điểm cao nhất: Tên chính xác khớp với query
    if (lowerName == lowerQuery) {
      score += 100;
    }
    // Tên bắt đầu bằng query
    else if (lowerName.startsWith(lowerQuery)) {
      score += 80;
    }
    // Tên chứa query
    else if (lowerName.contains(lowerQuery)) {
      score += 60;
      // Bonus nếu chứa toàn bộ từ
      if (lowerName.contains(' $lowerQuery ') ||
          lowerName.contains('$lowerQuery ') ||
          lowerName.contains(' $lowerQuery')) {
        score += 20;
      }
    }

    // Điểm cho description
    if (lowerDesc.contains(lowerQuery)) {
      score += 30;
    }

    // Điểm cho từng từ trong query
    List<String> queryWords = lowerQuery.split(' ');
    for (String word in queryWords) {
      if (word.length > 2) {
        // Chỉ tính các từ có ý nghĩa
        if (lowerName.contains(word)) {
          score += 15;
        }
        if (lowerDesc.contains(word)) {
          score += 10;
        }
      }
    }

    // Bonus cho các loại địa điểm phổ biến
    for (String type in result.types) {
      String lowerType = type.toLowerCase();
      if ([
        'shop',
        'amenity',
        'tourism',
        'leisure',
        'building',
      ].contains(lowerType)) {
        score += 10;
      }
    }

    // Penalty cho Plus Code (nếu vẫn còn)
    if (_isPlusCode(result.displayName)) {
      score -= 50;
    }

    return score;
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return ((lat1 - lat2).abs() + (lon1 - lon2).abs());
  }

  // Helper methods cho UI
  Color _getSourceColor(String source) {
    switch (source) {
      case 'geocoding':
        return Colors.blue;
      case 'nominatim':
        return Colors.green;
      case 'google_places':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getSourceIcon(String source) {
    switch (source) {
      case 'geocoding':
        return Icons.location_on;
      case 'nominatim':
        return Icons.map;
      case 'google_places':
        return Icons.business;
      default:
        return Icons.place;
    }
  }

  String _getSourceLabel(String source) {
    switch (source) {
      case 'geocoding':
        return 'Google';
      case 'nominatim':
        return 'OSM';
      case 'google_places':
        return 'Places';
      default:
        return 'Khác';
    }
  }

  Future<void> _selectSearchResult(int index) async {
    if (index >= 0 && index < _searchResults.length) {
      final result = _searchResults[index];
      _setSelectedPosition(LatLng(result.latitude, result.longitude));

      setState(() {
        _showSearchResults = false;
      });
      _searchController.clear();
    }
  }

  Future<void> _openInGoogleMaps() async {
    final LatLng center =
        _selectedPosition ??
        (_currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : const LatLng(21.0285, 105.8542));

    // Hướng dẫn user cách share từ Google Maps
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Hướng dẫn chia sẻ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Có 2 cách chia sẻ vị trí từ Google Maps:'),
              SizedBox(height: 16),

              // Cách 1: Share trực tiếp
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CÁCH 1: Chia sẻ trực tiếp (Khuyến nghị)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('1. Nhấn và giữ trên vị trí muốn chia sẻ'),
                    Text('2. Chọn "Chia sẻ" (Share)'),
                    Text('3. Chọn "LOCY" từ danh sách ứng dụng'),
                    Text('4. Vị trí sẽ tự động được thêm'),
                  ],
                ),
              ),

              SizedBox(height: 12),

              // Cách 2: Copy link
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CÁCH 2: Sao chép liên kết',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('1. Nhấn và giữ trên vị trí muốn chia sẻ'),
                    Text('2. Chọn "Chia sẻ" → "Sao chép liên kết"'),
                    Text('3. Quay lại ứng dụng LOCY'),
                    Text('4. Vị trí sẽ tự động được nhận diện'),
                  ],
                ),
              ),

              SizedBox(height: 12),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Đã hiểu'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _launchGoogleMaps(center);
            },
            child: Text('Mở Google Maps'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchGoogleMaps(LatLng center) async {
    final String url =
        'https://www.google.com/maps/@${center.latitude},${center.longitude},15z';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Cannot launch Google Maps');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể mở Google Maps'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cần quyền truy cập vị trí'),
        content: const Text(
          'Ứng dụng cần quyền truy cập vị trí để hiển thị vị trí hiện tại của bạn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Cài đặt'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lỗi'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chọn vị trí',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Bản đồ toàn màn hình
          _isLoadingLocation
              ? Container(
                  color: const Color(0xFFF8F9FA),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang lấy vị trí hiện tại...'),
                      ],
                    ),
                  ),
                )
              : GoogleMap(
                  onMapCreated: (GoogleMapController controller) {
                    _controller = controller;
                    if (_selectedPosition != null) {
                      controller.animateCamera(
                        CameraUpdate.newLatLng(_selectedPosition!),
                      );
                    }
                  },
                  initialCameraPosition: CameraPosition(
                    target:
                        _selectedPosition ??
                        (_currentPosition != null
                            ? LatLng(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                              )
                            : const LatLng(21.0285, 105.8542)),
                    zoom: 15,
                  ),
                  onTap: _onMapTap,
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),

          // Thanh tìm kiếm
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Nhập tên địa điểm...',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            _searchLocation(value);
                          },
                        ),
                      ),
                      if (_isSearching)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.map, color: Colors.blue),
                          onPressed: _openInGoogleMaps,
                          tooltip: 'Mở Google Maps',
                        ),
                    ],
                  ),
                ),

                // Danh sách kết quả tìm kiếm
                if (_showSearchResults && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];

                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getSourceColor(
                                result.source,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getSourceIcon(result.source),
                              color: _getSourceColor(result.source),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            result.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.description,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (result.types.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    children: result.types
                                        .take(2)
                                        .map(
                                          (type) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withOpacity(
                                                0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              type,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Text(
                            _getSourceLabel(result.source),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                          onTap: () => _selectSearchResult(index),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Nút xác nhận
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _selectedPosition != null
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddPlaceScreen(
                              latitude: _selectedPosition!.latitude,
                              longitude: _selectedPosition!.longitude,
                            ),
                          ),
                        ).then((result) {
                          if (result == true) {
                            Navigator.pop(context, true);
                          }
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedPosition != null
                      ? Colors.green
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: _selectedPosition != null
                          ? Colors.white
                          : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedPosition != null
                          ? 'Xác nhận vị trí'
                          : 'Chọn vị trí trên bản đồ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _selectedPosition != null
                            ? Colors.white
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
