import 'package:flutter/material.dart';
import '../services/location_share_service.dart';
import '../services/shared_data_state.dart';

// Ví dụ về cách sử dụng LocationShareService với modal processing
class MainAppExample extends StatefulWidget {
  @override
  _MainAppExampleState createState() => _MainAppExampleState();
}

class _MainAppExampleState extends State<MainAppExample> {
  @override
  void initState() {
    super.initState();
    _setupLocationShareService();
  }

  void _setupLocationShareService() {
    // Đăng ký location receiver từ Android intent
    LocationShareService.registerLocationReceiver();

    // Callback khi nhận được shared data từ intent
    LocationShareService.onSharedDataReceived = (locationText) {
      // Trigger modal processing
      LocationShareService.processSharedLocation(context, locationText);
    };

    // Callback khi xử lý shared location thành công
    LocationShareService.onSharedLocationProcessed = (location) {
      // Chuyển đến trang thêm địa điểm với location data
      _navigateToAddLocationPage(location);
    };

    // Callback khi có lỗi xử lý shared location
    LocationShareService.onSharedLocationError = (error) {
      // Log error hoặc handle error
      print('Shared location error: $error');
      // Reset state nếu cần
      SharedDataState.reset();
    };
  }

  void _navigateToAddLocationPage(Map<String, double> location) {
    // Thực hiện navigation đến trang thêm địa điểm
    Navigator.pushNamed(
      context,
      '/add-location',
      arguments: {
        'latitude': location['latitude'],
        'longitude': location['longitude'],
        'isFromShared': true, // Đánh dấu là từ shared data
      },
    );
  }

  // Hàm check clipboard khi app resume hoặc user action
  Future<void> _checkClipboard() async {
    await LocationShareService.checkAndProcessClipboard(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Location Share Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('App sẽ tự động xử lý khi nhận được data từ Google Maps'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkClipboard,
              child: Text('Kiểm tra Clipboard'),
            ),
            SizedBox(height: 10),
            Text(
              'Hoặc có thể check clipboard thủ công',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Clean up callbacks
    LocationShareService.onSharedDataReceived = null;
    LocationShareService.onSharedLocationProcessed = null;
    LocationShareService.onSharedLocationError = null;
    super.dispose();
  }
}
