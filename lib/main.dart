import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'screens/add_place_screen.dart';
import 'services/location_share_service.dart';
import 'services/shared_data_state.dart';
import 'config/app_config.dart';

// Tạo RouteObserver để theo dõi navigation
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isProcessingLocation = false; // Thêm cờ để tránh xử lý trùng lặp

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Hủy đăng ký callbacks
    LocationShareService.onSharedDataReceived = null;
    LocationShareService.onSharedLocationProcessed = null;
    LocationShareService.onSharedLocationError = null;
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Setup callbacks cho shared data processing
    LocationShareService.onSharedDataReceived = (locationText) {
      // Khi nhận được shared data, xử lý với modal loading
      final context = _navigatorKey.currentContext;
      if (context != null) {
        LocationShareService.processSharedLocation(context, locationText);
      }
    };

    LocationShareService.onSharedLocationProcessed = (location) {
      // Khi xử lý thành công, chuyển đến trang thêm địa điểm
      print('Shared location processed successfully: $location');
      _navigateToAddPlace(location);
    };

    LocationShareService.onSharedLocationError = (error) {
      // Log lỗi xử lý shared data
      print('Shared location processing error: $error');
      SharedDataState.reset();
    };

    // Đăng ký receiver để lắng nghe các intent đến khi app đang chạy
    await LocationShareService.registerLocationReceiver();

    // Kiểm tra intent ban đầu khi app khởi động từ trạng thái terminated
    Future.delayed(const Duration(milliseconds: 500), () {
      _checkForInitialSharedLocation();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Khi app được resumed, kiểm tra clipboard (với logic mới)
    if (state == AppLifecycleState.resumed) {
      print('App resumed, checking for shared location from clipboard.');
      Future.delayed(const Duration(milliseconds: 500), () {
        _checkClipboardForSharedLocation();
      });
    }
  }

  // Kiểm tra intent data khi app khởi động
  Future<void> _checkForInitialSharedLocation() async {
    if (_isProcessingLocation) return;

    setState(() {
      _isProcessingLocation = true;
    });

    try {
      final intentData = await LocationShareService.getIntentData();
      if (intentData != null && intentData['data'] != null) {
        print('Initial intent data found: ${intentData['data']}');
        final context = _navigatorKey.currentContext;
        if (context != null) {
          await LocationShareService.processSharedLocation(
            context,
            intentData['data']!,
          );
        }
        await LocationShareService.clearIntentData();
      }
    } catch (e) {
      print('Error checking initial shared location: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingLocation = false;
        });
      }
    }
  }

  // Kiểm tra clipboard an toàn (không tự động parse)
  Future<void> _checkClipboardForSharedLocation() async {
    if (_isProcessingLocation ||
        SharedDataState.isProcessing ||
        SharedDataState.wasRecentlyProcessed) {
      print(
        'Skipping clipboard check - already processing or recently processed',
      );
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context != null) {
      await LocationShareService.checkAndProcessClipboard(context);
    }
  }

  void _navigateToAddPlace(Map<String, double> location) {
    print('Navigating to AddPlaceScreen with location: $location');
    if (_navigatorKey.currentState == null) {
      print('Navigator state is null, cannot navigate.');
      return;
    }

    // Sử dụng `currentState` đã được kiểm tra non-null
    final navigator = _navigatorKey.currentState!;

    // Đảm bảo không có dialog hay bottom sheet nào đang mở
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }

    // Đẩy trang mới lên đầu stack, thay thế trang home hiện tại
    // Điều này giúp tránh việc back lại trang home trống rỗng
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => AddPlaceScreen(
          latitude: location['latitude']!,
          longitude: location['longitude']!,
        ),
        settings: const RouteSettings(
          name: '/add_place',
        ), // Đặt tên để nhận biết
      ),
      (route) => route.isFirst, // Xóa tất cả các route trước đó
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      navigatorKey: _navigatorKey,
      navigatorObservers: [routeObserver], // Thêm RouteObserver
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
