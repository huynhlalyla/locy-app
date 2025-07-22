import 'package:flutter/material.dart';
import '../models/place.dart';
import '../services/storage_service.dart';
import '../widgets/place_card.dart';
import 'map_picker_screen.dart';
import 'edit_place_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart'; // Import để sử dụng routeObserver

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  final StorageService _storageService = StorageService();
  List<Place> _places = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlaces();
    _debugStorage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Đăng ký RouteObserver với type casting đúng
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // RouteAware callbacks - Sẽ được gọi khi route này được active
  @override
  void didPopNext() {
    // Được gọi khi quay về trang này từ trang khác
    print('HomeScreen: didPopNext - Refreshing data');
    _loadPlaces();
  }

  @override
  void didPop() {
    // Được gọi khi trang này được pop
    print('HomeScreen: didPop');
  }

  @override
  void didPush() {
    // Được gọi khi trang này được push
    print('HomeScreen: didPush');
  }

  @override
  void didPushNext() {
    // Được gọi khi navigate từ trang này sang trang khác
    print('HomeScreen: didPushNext');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh dữ liệu khi app được resumed
      print('HomeScreen: App resumed - Refreshing data');
      _loadPlaces();
    }
  }

  // Sử dụng didUpdateWidget để refresh khi quay về trang
  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPlaces();
  }

  // Thêm method để refresh từ bên ngoài
  Future<void> refreshPlaces() async {
    await _loadPlaces();
  }

  Future<void> _debugStorage() async {
    await _storageService.debugStorage();
  }

  Future<void> _loadPlaces() async {
    setState(() {
      _isLoading = true;
    });

    final places = await _storageService.loadPlaces();

    setState(() {
      _places = places;
      _isLoading = false;
    });
  }

  Future<void> _deletePlace(String id) async {
    await _storageService.deletePlace(id);
    _loadPlaces();
  }

  Future<void> _editPlace(Place place) async {
    // Chuyển đến trang chỉnh sửa với dữ liệu hiện tại
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPlaceScreen(place: place),
      ),
    );
    
    // Nếu cập nhật thành công, refresh danh sách
    if (result == true) {
      _loadPlaces();
    }
  }  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LOCY',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // Header section
            _buildHeader(),
            // Main content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadPlaces,
                      child: _places.isEmpty
                          ? _buildEmptyState()
                          : _buildPlacesList(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MapPickerScreen()),
          );
          if (result == true) {
            _loadPlaces();
          }
        },
        label: const Text('Thêm địa điểm'),
        icon: const Icon(Icons.add_location),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blue, Colors.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo và tên ứng dụng
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'LOCY',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Quản lý địa điểm thông minh',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          // Số lượng địa điểm đã lưu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bookmark, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  '${_places.length} địa điểm đã lưu',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 100),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(Icons.location_off, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Hiện chưa có địa điểm nào được lưu.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Hãy thêm địa điểm mới nào!',
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlacesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _places.length,
      itemBuilder: (context, index) {
        final place = _places[index];
        return PlaceCard(
          place: place,
          onDelete: () => _deletePlace(place.id),
          onTap: () => _openInGoogleMaps(place),
          onEdit: () => _editPlace(place),
        );
      },
    );
  }

  Future<void> _openInGoogleMaps(Place place) async {
    // Thử các URL theo thứ tự ưu tiên
    final List<String> urls = [
      // Google Maps với chỉ đường - URL chính thức
      'https://www.google.com/maps/dir/?api=1&destination=${place.latitude},${place.longitude}&travelmode=driving',
      // Google Maps app scheme
      'google.navigation:q=${place.latitude},${place.longitude}&mode=d',
      // Geo URI với Google Maps
      'geo:${place.latitude},${place.longitude}?q=${place.latitude},${place.longitude}(${Uri.encodeComponent(place.name)})',
      // Maps app intent
      'https://maps.google.com/maps?daddr=${place.latitude},${place.longitude}',
      // Fallback web URL
      'https://maps.google.com/?q=${place.latitude},${place.longitude}',
    ];

    bool success = false;

    for (String url in urls) {
      try {
        final uri = Uri.parse(url);

        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_blank',
          );
          success = true;
          break;
        }
      } catch (e) {
        continue; // Thử URL tiếp theo
      }
    }

    // Nếu tất cả URL đều thất bại, hiển thị thông báo lỗi đơn giản
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Có lỗi khi mở bản đồ. Vui lòng thử lại.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
