import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import '../config/app_config.dart';
import '../widgets/location_processing_modal.dart';
import 'shared_data_state.dart';

class LocationShareService {
  static const MethodChannel _intentChannel = MethodChannel(
    AppConfig.intentChannelName,
  );
  static const MethodChannel _locationReceiverChannel = MethodChannel(
    AppConfig.locationReceiverChannelName,
  );

  // Callback cho khi nhận được dữ liệu vị trí
  static void Function(Map<String, double>)? onLocationReceived;

  // Callback cho khi xử lý thành công dữ liệu chia sẻ
  static void Function(Map<String, double>)? onSharedLocationProcessed;

  // Callback cho khi có lỗi xử lý dữ liệu chia sẻ
  static void Function(String)? onSharedLocationError;

  // Callback cho khi có shared data cần xử lý
  static void Function(String)? onSharedDataReceived;

  // Lưu trữ tạm shared data
  static String? _pendingSharedData;

  // Đăng ký location receiver và thiết lập listener
  static Future<void> registerLocationReceiver() async {
    try {
      await _locationReceiverChannel.invokeMethod('register');

      // Thiết lập method call handler để nhận dữ liệu từ Android
      _intentChannel.setMethodCallHandler((call) async {
        if (call.method == 'onLocationReceived') {
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          final String? locationText = data['data'];

          // Chỉ xử lý khi có dữ liệu thực sự và không rỗng
          if (locationText != null &&
              locationText.trim().isNotEmpty &&
              locationText.trim().length > 3) {
            // Tránh dữ liệu rác quá ngắn

            // Lưu shared data và trigger callback
            _pendingSharedData = locationText;
            if (onSharedDataReceived != null) {
              onSharedDataReceived!(locationText);
            }
          }
        }
      });
    } catch (e) {
      print('Error registering location receiver: $e');
    }
  }

  // Kiểm tra và yêu cầu quyền truy cập vị trí
  static Future<bool> checkLocationPermission() async {
    try {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
      }
      return status.isGranted;
    } catch (e) {
      print('Error checking location permission: $e');
      return false;
    }
  }

  // Lấy vị trí hiện tại
  static Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return position;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  // Lấy và xóa pending shared data
  static String? getPendingSharedData() {
    final data = _pendingSharedData;
    _pendingSharedData = null;
    return data;
  }

  // Xử lý dữ liệu chia sẻ với modal loading
  static Future<void> processSharedLocation(
    BuildContext context,
    String locationText,
  ) async {
    // Kiểm tra xem có đang process không
    if (SharedDataState.isProcessing) {
      return;
    }

    // Set trạng thái processing
    SharedDataState.setProcessing(true);

    // Hiển thị modal loading
    LocationProcessingModal.show(context, 'Đang phân tích dữ liệu chia sẻ...');

    try {
      // Xóa clipboard ngay lập tức để tránh detect lại
      await clearLocationFromClipboard();

      // Phân tích dữ liệu location
      final location = await parseLocationFromText(locationText);

      // Ẩn modal loading
      LocationProcessingModal.hide(context);

      if (location != null) {
        // Thành công - clear clipboard và gọi callback để chuyển đến trang thêm địa điểm
        await SharedDataState.clearClipboard();
        if (onSharedLocationProcessed != null) {
          onSharedLocationProcessed!(location);
        }
      } else {
        // Lỗi phân tích - clear clipboard và hiển thị modal lỗi
        await SharedDataState.clearClipboard();
        LocationProcessingModal.showError(
          context,
          'Không thể phân tích dữ liệu được chia sẻ. Vui lòng thử lại với link Google Maps khác.',
          onDismiss: () {
            if (onSharedLocationError != null) {
              onSharedLocationError!('Parse failed');
            }
          },
        );
      }
    } catch (e) {
      // Ẩn modal loading nếu có lỗi
      LocationProcessingModal.hide(context);

      // Clear clipboard và hiển thị modal lỗi
      await SharedDataState.clearClipboard();
      LocationProcessingModal.showError(
        context,
        'Có lỗi xảy ra khi xử lý dữ liệu chia sẻ. Vui lòng thử lại.',
        onDismiss: () {
          if (onSharedLocationError != null) {
            onSharedLocationError!('Processing error: $e');
          }
        },
      );
    } finally {
      // Reset trạng thái processing
      SharedDataState.setProcessing(false);
    }
  }

  // Kiểm tra và xử lý dữ liệu clipboard với modal
  // Kiểm tra xem có dữ liệu vị trí trong clipboard không (không auto-parse)
  static Future<String?> checkClipboardForLocationText() async {
    try {
      // Nếu vừa process gần đây thì không check clipboard
      if (SharedDataState.wasRecentlyProcessed ||
          SharedDataState.isProcessing) {
        return null;
      }

      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        final String text = data.text!.trim();
        if (_containsLocationData(text)) {
          return text;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Kiểm tra và xử lý clipboard với modal (phiên bản mới)
  static Future<void> checkAndProcessClipboard(BuildContext context) async {
    final locationText = await checkClipboardForLocationText();
    if (locationText != null) {
      await processSharedLocation(context, locationText);
    }
  }

  // Xóa dữ liệu vị trí khỏi clipboard
  static Future<void> clearLocationFromClipboard() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (e) {
      print('Error clearing clipboard: $e');
    }
  }

  // Cải thiện parse location với nhiều format Google Maps
  static Future<Map<String, double>?> parseLocationFromText(String text) async {
    try {
      final String cleanText = text.trim();

      // Kiểm tra dữ liệu có hợp lệ không - tránh parse dữ liệu rác
      if (cleanText.isEmpty || cleanText.length < 5) {
        return null;
      }

      // Chỉ xử lý nếu có dấu hiệu của URL hoặc coordinates
      if (!_containsLocationData(cleanText)) {
        return null;
      }

      // Format 1: Tọa độ đơn giản "latitude,longitude"
      final RegExp coordRegex = RegExp(r'^-?\d+\.?\d*,-?\d+\.?\d*$');
      if (coordRegex.hasMatch(cleanText)) {
        final coords = cleanText.split(',');
        if (coords.length == 2) {
          final lat = double.tryParse(coords[0].trim());
          final lng = double.tryParse(coords[1].trim());
          if (lat != null &&
              lng != null &&
              await _isValidAndDistantCoordinate(lat, lng)) {
            return {'latitude': lat, 'longitude': lng};
          }
        }
      }

      // Format 2: Google Maps URL patterns
      final googleMapsLocation = _parseGoogleMapsUrl(cleanText);
      if (googleMapsLocation != null) {
        final lat = googleMapsLocation['latitude']!;
        final lng = googleMapsLocation['longitude']!;
        if (await _isValidAndDistantCoordinate(lat, lng)) {
          return googleMapsLocation;
        }
      }

      // Format 3: Google Maps short URL
      final shortUrlLocation = await _parseGoogleMapsShortUrl(cleanText);
      if (shortUrlLocation != null) {
        final lat = shortUrlLocation['latitude']!;
        final lng = shortUrlLocation['longitude']!;
        if (await _isValidAndDistantCoordinate(lat, lng)) {
          return shortUrlLocation;
        }
      }

      // Format 4: Geo URI (geo:latitude,longitude)
      final geoUriLocation = _parseGeoUri(cleanText);
      if (geoUriLocation != null) {
        final lat = geoUriLocation['latitude']!;
        final lng = geoUriLocation['longitude']!;
        if (await _isValidAndDistantCoordinate(lat, lng)) {
          return geoUriLocation;
        }
      }

      // Format 5: Plus codes
      final plusCodeLocation = await _parsePlusCode(cleanText);
      if (plusCodeLocation != null) {
        final lat = plusCodeLocation['latitude']!;
        final lng = plusCodeLocation['longitude']!;
        if (await _isValidAndDistantCoordinate(lat, lng)) {
          return plusCodeLocation;
        }
      }

      // Format 6: Tìm kiếm tọa độ trong text dài
      final extractedLocation = _extractCoordinatesFromText(cleanText);
      if (extractedLocation != null) {
        final lat = extractedLocation['latitude']!;
        final lng = extractedLocation['longitude']!;
        if (await _isValidAndDistantCoordinate(lat, lng)) {
          return extractedLocation;
        }
      }

      // Format 7: Fallback - Parse bất kỳ URL nào có thể chứa coordinates
      final fallbackLocation = await _fallbackUrlParsing(cleanText);
      if (fallbackLocation != null) {
        final lat = fallbackLocation['latitude']!;
        final lng = fallbackLocation['longitude']!;
        if (await _isValidAndDistantCoordinate(lat, lng)) {
          return fallbackLocation;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Kiểm tra tọa độ hợp lệ và không quá gần vị trí hiện tại
  static Future<bool> _isValidAndDistantCoordinate(
    double latitude,
    double longitude,
  ) async {
    // Kiểm tra validation cơ bản trước
    if (!_isValidCoordinate(latitude, longitude)) {
      return false;
    }

    try {
      // Lấy vị trí hiện tại để so sánh
      final currentPosition = await getCurrentLocation();

      if (currentPosition != null) {
        // Tính khoảng cách giữa tọa độ được parse và vị trí hiện tại
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          latitude,
          longitude,
        );

        // Nếu khoảng cách < 50m, có thể là dữ liệu ảo từ GPS cache
        // Trừ khi có độ chính xác rất cao (thực sự được share từ Maps)
        if (distance < 50) {
          final precision =
              _countDecimalPlaces(latitude) + _countDecimalPlaces(longitude);

          // Nếu độ chính xác thấp (< 8 chữ số thập phân tổng) thì reject
          if (precision < 8) {
            print(
              'Rejected coordinate too close to current location: ${distance}m, precision: $precision',
            );
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      // Nếu không thể lấy vị trí hiện tại, vẫn cho phép coordinate
      return true;
    }
  }

  // Kiểm tra xem text có chứa dữ liệu location không
  static bool _containsLocationData(String text) {
    final String lowerText = text.toLowerCase();

    // Kiểm tra có URL hoặc geo data
    if (lowerText.contains('http') ||
        lowerText.contains('maps') ||
        lowerText.contains('geo:') ||
        lowerText.contains('goo.gl') ||
        lowerText.contains('maps.app.goo.gl')) {
      return true;
    }

    // Kiểm tra có pattern coordinates
    if (RegExp(r'-?\d+\.?\d*\s*,\s*-?\d+\.?\d*').hasMatch(text)) {
      return true;
    }

    // Kiểm tra có plus code
    if (RegExp(
      r'[23456789CFGHJMPQRVWX]{8}\+[23456789CFGHJMPQRVWX]{2,3}',
    ).hasMatch(text)) {
      return true;
    }

    return false;
  }

  // Fallback parsing cho bất kỳ URL nào
  static Future<Map<String, double>?> _fallbackUrlParsing(String text) async {
    try {
      if (!text.contains('http')) return null;

      final response = await http.get(
        Uri.parse(text),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );

      if (response.statusCode == 200) {
        final content = response.body;

        final metaCoords = _extractCoordsFromMeta(content);
        if (metaCoords != null) return metaCoords;

        final jsCoords = _extractCoordsFromJavaScript(content);
        if (jsCoords != null) return jsCoords;

        final dataCoords = _extractCoordsFromDataAttributes(content);
        if (dataCoords != null) return dataCoords;

        final jsonLdCoords = _extractCoordsFromJsonLd(content);
        if (jsonLdCoords != null) return jsonLdCoords;

        final aggressiveCoords = _aggressiveContentSearch(content);
        if (aggressiveCoords != null) return aggressiveCoords;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Tìm kiếm aggressive trong toàn bộ content
  static Map<String, double>? _aggressiveContentSearch(String content) {
    try {
      final List<RegExp> aggressivePatterns = [
        RegExp(r'([+-]?\d{1,3}\.\d{4,})[,\s]+([+-]?\d{1,3}\.\d{4,})'),
        RegExp(
          r'\{[^}]*"lat"[^}]*([+-]?\d+\.\d+)[^}]*"lng"[^}]*([+-]?\d+\.\d+)[^}]*\}',
        ),
        RegExp(
          r'\{[^}]*"lng"[^}]*([+-]?\d+\.\d+)[^}]*"lat"[^}]*([+-]?\d+\.\d+)[^}]*\}',
        ),
        RegExp(r'\[\s*([+-]?\d+\.\d{4,})\s*,\s*([+-]?\d+\.\d{4,})\s*\]'),
        RegExp(r'LatLng\s*\(\s*([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)\s*\)'),
        RegExp(r'setCenter\s*\(\s*([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)\s*\)'),
        RegExp(
          r'data-[a-z-]*lat[a-z-]*=["\x27]([+-]?\d+\.\d+)["\x27].*data-[a-z-]*lng[a-z-]*=["\x27]([+-]?\d+\.\d+)["\x27]',
        ),
        RegExp(
          r'data-[a-z-]*lng[a-z-]*=["\x27]([+-]?\d+\.\d+)["\x27].*data-[a-z-]*lat[a-z-]*=["\x27]([+-]?\d+\.\d+)["\x27]',
        ),
      ];

      final validPairs = <Map<String, double>>[];

      for (final pattern in aggressivePatterns) {
        final matches = pattern.allMatches(content);
        for (final match in matches) {
          double? lat, lng;

          if (pattern.pattern.contains('"lng".*"lat"') ||
              pattern.pattern.contains('lng[a-z-]*.*lat')) {
            lng = double.tryParse(match.group(1)!);
            lat = double.tryParse(match.group(2)!);
          } else {
            lat = double.tryParse(match.group(1)!);
            lng = double.tryParse(match.group(2)!);
          }

          if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
            validPairs.add({'latitude': lat, 'longitude': lng});
          }
        }
      }

      if (validPairs.isNotEmpty) {
        validPairs.sort((a, b) {
          final scoreA = _calculateRealismScore(
            a['latitude']!,
            a['longitude']!,
          );
          final scoreB = _calculateRealismScore(
            b['latitude']!,
            b['longitude']!,
          );
          return scoreB.compareTo(scoreA);
        });

        return validPairs.first;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Parse Google Maps URL với nhiều pattern
  static Map<String, double>? _parseGoogleMapsUrl(String text) {
    try {
      print('Parsing Google Maps URL: $text');

      // Pattern 1: https://maps.google.com/maps?q=latitude,longitude
      final RegExp pattern1 = RegExp(
        r'https?://(?:www\.)?(?:maps\.)?google\.com/maps.*[?&]q=([^&]+)',
      );
      final match1 = pattern1.firstMatch(text);
      if (match1 != null) {
        final coordinates = Uri.decodeComponent(match1.group(1)!);
        print('Pattern1 coordinates: $coordinates');
        final coordMatch = RegExp(
          r'(-?\d+\.?\d+),(-?\d+\.?\d+)', // Yêu cầu ít nhất 1 chữ số thập phân
        ).firstMatch(coordinates);
        if (coordMatch != null) {
          final lat = double.tryParse(coordMatch.group(1)!);
          final lng = double.tryParse(coordMatch.group(2)!);
          print('Pattern1 parsed: lat=$lat, lng=$lng');
          if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
            return {'latitude': lat, 'longitude': lng};
          }
        }
      }

      // Pattern 2: https://maps.google.com/maps?q=@latitude,longitude,zoom
      final RegExp pattern2 = RegExp(
        r'https?://(?:www\.)?(?:maps\.)?google\.com/maps.*[@](-?\d+\.?\d+),(-?\d+\.?\d+)',
      );
      final match2 = pattern2.firstMatch(text);
      if (match2 != null) {
        final lat = double.tryParse(match2.group(1)!);
        final lng = double.tryParse(match2.group(2)!);
        print('Pattern2 parsed: lat=$lat, lng=$lng');
        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }

      // Pattern 3: https://maps.google.com/?q=latitude,longitude
      final RegExp pattern3 = RegExp(
        r'https?://(?:www\.)?(?:maps\.)?google\.com/.*[?&]q=(-?\d+\.?\d+),(-?\d+\.?\d+)',
      );
      final match3 = pattern3.firstMatch(text);
      if (match3 != null) {
        final lat = double.tryParse(match3.group(1)!);
        final lng = double.tryParse(match3.group(2)!);
        print('Pattern3 parsed: lat=$lat, lng=$lng');
        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }

      // Pattern 4: https://maps.google.com/maps/place/.../@latitude,longitude
      final RegExp pattern4 = RegExp(
        r'https?://(?:www\.)?(?:maps\.)?google\.com/maps/place/.*/@(-?\d+\.?\d+),(-?\d+\.?\d+)',
      );
      final match4 = pattern4.firstMatch(text);
      if (match4 != null) {
        final lat = double.tryParse(match4.group(1)!);
        final lng = double.tryParse(match4.group(2)!);
        print('Pattern4 parsed: lat=$lat, lng=$lng');
        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }

      // Pattern 7: Extract từ URL fragment (phần sau dấu #)
      final RegExp fragmentPattern = RegExp(r'#.*?(-?\d+\.?\d+),(-?\d+\.?\d+)');
      final fragmentMatch = fragmentPattern.firstMatch(text);
      if (fragmentMatch != null) {
        final lat = double.tryParse(fragmentMatch.group(1)!);
        final lng = double.tryParse(fragmentMatch.group(2)!);
        print('Fragment parsed: lat=$lat, lng=$lng');
        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }

      // Pattern 8: Tìm kiếm tất cả số thập phân trong URL với độ chính xác cao
      final List<double> allNumbers = [];
      final RegExp numberPattern = RegExp(
        r'(-?\d+\.\d{4,})',
      ); // Ít nhất 4 chữ số thập phân
      final numberMatches = numberPattern.allMatches(text);
      for (final match in numberMatches) {
        final num = double.tryParse(match.group(1)!);
        if (num != null) allNumbers.add(num);
      }
      print('Found numbers with high precision: $allNumbers');

      // Tìm cặp số hợp lệ cho latitude, longitude
      for (int i = 0; i < allNumbers.length - 1; i++) {
        final lat = allNumbers[i];
        final lng = allNumbers[i + 1];
        print('Checking pair: lat=$lat, lng=$lng');
        if (_isValidCoordinate(lat, lng)) {
          print('Valid coordinate pair found!');
          return {'latitude': lat, 'longitude': lng};
        }
      }

      // Pattern mở rộng: Tìm bất kỳ cặp số nào có thể là tọa độ
      final RegExp generalPattern = RegExp(
        r'(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)',
      );
      final generalMatches = generalPattern.allMatches(text);
      for (final match in generalMatches) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        print('General pattern parsed: lat=$lat, lng=$lng');
        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }

      // Pattern 6: Google Maps search URL with query parameter
      final RegExp pattern6 = RegExp(
        r'https?://(?:www\.)?google\.com/maps/search.*[?&]query=([^&]+)',
      );
      final match6 = pattern6.firstMatch(text);
      if (match6 != null) {
        final coords = Uri.decodeComponent(match6.group(1)!);
        final coordMatch = RegExp(
          r'(-?\d+\.?\d*),(-?\d+\.?\d*)',
        ).firstMatch(coords);
        if (coordMatch != null) {
          final lat = double.tryParse(coordMatch.group(1)!);
          final lng = double.tryParse(coordMatch.group(2)!);
          if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
            return {'latitude': lat, 'longitude': lng};
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Parse Google Maps short URL với HTTP request
  // Parse Google Maps short URL với HTTP redirect handling và web scraping
  static Future<Map<String, double>?> _parseGoogleMapsShortUrl(
    String text,
  ) async {
    try {
      final RegExp shortUrlRegex = RegExp(
        r'https?://(?:goo\.gl/maps/|maps\.app\.goo\.gl/)\S+',
      );
      final match = shortUrlRegex.firstMatch(text);
      if (match != null) {
        final shortUrl = match.group(0)!;

        // Phương pháp 1: Theo dõi redirect chains
        final redirectResult = await _followRedirects(shortUrl);
        if (redirectResult != null) {
          final parsedFromRedirect = _parseGoogleMapsUrl(redirectResult);
          if (parsedFromRedirect != null) {
            return parsedFromRedirect;
          }
        }

        // Phương pháp 2: Fetch HTML content và tìm kiếm trong meta tags và JavaScript
        final htmlResult = await _parseFromHtmlContent(shortUrl);
        if (htmlResult != null) {
          return htmlResult;
        }

        // Phương pháp 3: Thử với Google Maps Embed API endpoint
        final embedResult = await _tryGoogleMapsEmbed(shortUrl);
        if (embedResult != null) {
          return embedResult;
        }
      } else {
        // No short URL matched
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Theo dõi redirect chains một cách chi tiết
  static Future<String?> _followRedirects(String url) async {
    try {
      final client = http.Client();
      String currentUrl = url;
      int redirectCount = 0;
      const maxRedirects = 10;

      while (redirectCount < maxRedirects) {
        final request = http.Request('GET', Uri.parse(currentUrl));
        request.headers.addAll({
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
        });

        final streamedResponse = await client.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          client.close();
          return currentUrl;
        } else if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            currentUrl = location.startsWith('http')
                ? location
                : Uri.parse(currentUrl).resolve(location).toString();
            redirectCount++;
          } else {
            break;
          }
        } else {
          break;
        }
      }

      client.close();
      return currentUrl;
    } catch (e) {
      return null;
    }
  }

  // Parse coordinates từ HTML content
  static Future<Map<String, double>?> _parseFromHtmlContent(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );

      if (response.statusCode == 200) {
        final htmlContent = response.body;

        // Tìm trong meta tags
        final metaCoords = _extractCoordsFromMeta(htmlContent);
        if (metaCoords != null) return metaCoords;

        // Tìm trong JavaScript variables
        final jsCoords = _extractCoordsFromJavaScript(htmlContent);
        if (jsCoords != null) return jsCoords;

        // Tìm trong data attributes
        final dataCoords = _extractCoordsFromDataAttributes(htmlContent);
        if (dataCoords != null) return dataCoords;

        // Tìm trong JSON-LD structured data
        final jsonLdCoords = _extractCoordsFromJsonLd(htmlContent);
        if (jsonLdCoords != null) return jsonLdCoords;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Extract coordinates từ meta tags
  static Map<String, double>? _extractCoordsFromMeta(String html) {
    try {
      // Meta tag patterns
      final List<RegExp> metaPatterns = [
        RegExp(
          r'<meta[^>]*property=["\x27]og:latitude["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ),
        RegExp(
          r'<meta[^>]*name=["\x27]latitude["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ),
        RegExp(
          r'<meta[^>]*property=["\x27]place:location:latitude["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ),
      ];

      final List<RegExp> lngPatterns = [
        RegExp(
          r'<meta[^>]*property=["\x27]og:longitude["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ),
        RegExp(
          r'<meta[^>]*name=["\x27]longitude["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ),
        RegExp(
          r'<meta[^>]*property=["\x27]place:location:longitude["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ),
      ];

      double? lat, lng;

      for (final pattern in metaPatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          lat = double.tryParse(match.group(1)!);
          if (lat != null) break;
        }
      }

      for (final pattern in lngPatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          lng = double.tryParse(match.group(1)!);
          if (lng != null) break;
        }
      }

      if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
        return {'latitude': lat, 'longitude': lng};
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Extract coordinates từ JavaScript variables
  static Map<String, double>? _extractCoordsFromJavaScript(String html) {
    try {
      final List<RegExp> jsPatterns = [
        // Standard JSON format
        RegExp(r'"latitude"\s*:\s*([+-]?\d+\.?\d*)', caseSensitive: false),
        RegExp(r'"longitude"\s*:\s*([+-]?\d+\.?\d*)', caseSensitive: false),
        RegExp(r'"lat"\s*:\s*([+-]?\d+\.?\d*)', caseSensitive: false),
        RegExp(r'"lng"\s*:\s*([+-]?\d+\.?\d*)', caseSensitive: false),

        // Object patterns
        RegExp(
          r'center:\s*\{\s*lat:\s*([+-]?\d+\.?\d*)\s*,\s*lng:\s*([+-]?\d+\.?\d*)',
          caseSensitive: false,
        ),

        // Array patterns
        RegExp(r'\[([+-]?\d+\.?\d*),\s*([+-]?\d+\.?\d*)\]'), // [lat, lng]
        // Google-specific patterns
        RegExp(
          r'window\.APP_INITIALIZATION_STATE.*?(-?\d+\.?\d*),(-?\d+\.?\d*)',
        ),
        RegExp(r'window\.APP_OPTIONS.*?(-?\d+\.?\d*),(-?\d+\.?\d*)'),
        RegExp(r'_pageData.*?(-?\d+\.?\d*),(-?\d+\.?\d*)'),

        // URL-encoded patterns trong JavaScript
        RegExp(r'%22lat%22%3A([+-]?\d+\.?\d*)'),
        RegExp(r'%22lng%22%3A([+-]?\d+\.?\d*)'),

        // Coordinates trong string literals
        RegExp(
          r'coords?\s*[=:]\s*["\x27]([+-]?\d+\.?\d*),([+-]?\d+\.?\d*)["\x27]',
        ),

        // Google Maps API center parameter
        RegExp(
          r'center\s*=\s*new\s+google\.maps\.LatLng\s*\(\s*([+-]?\d+\.?\d*)\s*,\s*([+-]?\d+\.?\d*)\s*\)',
        ),

        // Viewport bounds
        RegExp(
          r'viewport.*?([+-]?\d+\.?\d*),([+-]?\d+\.?\d*),([+-]?\d+\.?\d*),([+-]?\d+\.?\d*)',
        ),
      ];

      for (final pattern in jsPatterns) {
        final matches = pattern.allMatches(html);
        for (final match in matches) {
          double? lat, lng;

          if (match.groupCount >= 2) {
            // Pattern có 2+ groups
            if (pattern.pattern.contains('viewport') && match.groupCount >= 4) {
              // Viewport bounds: [sw_lat, sw_lng, ne_lat, ne_lng]
              final swLat = double.tryParse(match.group(1)!);
              final swLng = double.tryParse(match.group(2)!);
              final neLat = double.tryParse(match.group(3)!);
              final neLng = double.tryParse(match.group(4)!);

              if (swLat != null &&
                  swLng != null &&
                  neLat != null &&
                  neLng != null) {
                // Tính center từ bounds
                lat = (swLat + neLat) / 2;
                lng = (swLng + neLng) / 2;
              }
            } else {
              lat = double.tryParse(match.group(1)!);
              lng = double.tryParse(match.group(2)!);
            }
          } else if (pattern.pattern.contains('latitude')) {
            // Tìm latitude trước, sau đó tìm longitude gần nó
            lat = double.tryParse(match.group(1)!);
            final lngPattern = RegExp(
              r'"longitude"\s*:\s*([+-]?\d+\.?\d*)',
              caseSensitive: false,
            );
            final lngMatch = lngPattern.firstMatch(
              html.substring(
                match.end,
                math.min(html.length, match.end + 1000),
              ),
            );
            if (lngMatch != null) {
              lng = double.tryParse(lngMatch.group(1)!);
            }
          } else if (pattern.pattern.contains('lat%22')) {
            // URL encoded latitude, tìm longitude tương ứng
            lat = double.tryParse(match.group(1)!);
            final lngPattern = RegExp(r'%22lng%22%3A([+-]?\d+\.?\d*)');
            final lngMatch = lngPattern.firstMatch(
              html.substring(
                math.max(0, match.start - 1000),
                math.min(html.length, match.end + 1000),
              ),
            );
            if (lngMatch != null) {
              lng = double.tryParse(lngMatch.group(1)!);
            }
          } else if (pattern.pattern.contains('"lat"')) {
            lat = double.tryParse(match.group(1)!);
            // Tìm lng pattern trong cùng context
            final nearbyText = html.substring(
              math.max(0, match.start - 200),
              math.min(html.length, match.end + 200),
            );
            final lngPattern = RegExp(
              r'"lng"\s*:\s*([+-]?\d+\.?\d*)',
              caseSensitive: false,
            );
            final lngMatch = lngPattern.firstMatch(nearbyText);
            if (lngMatch != null) {
              lng = double.tryParse(lngMatch.group(1)!);
            }
          }

          if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
            return {'latitude': lat, 'longitude': lng};
          }
        }
      }

      // Fallback: tìm kiếm aggressive hơn trong toàn bộ JavaScript
      final aggressiveCoords = _aggressiveJavaScriptSearch(html);
      if (aggressiveCoords != null) return aggressiveCoords;

      return null;
    } catch (e) {
      return null;
    }
  }

  // Tìm kiếm aggressive trong JavaScript content
  static Map<String, double>? _aggressiveJavaScriptSearch(String html) {
    try {
      // Tìm tất cả các số thập phân với ít nhất 4 chữ số sau dấu phẩy
      final RegExp preciseNumberPattern = RegExp(r'([+-]?\d{1,3}\.\d{4,})');
      final allPreciseNumbers = <double>[];

      final matches = preciseNumberPattern.allMatches(html);
      for (final match in matches) {
        final num = double.tryParse(match.group(1)!);
        if (num != null) {
          allPreciseNumbers.add(num);
        }
      }

      // Sắp xếp để ưu tiên các cặp coordinates có vẻ thực tế hơn
      final validPairs = <Map<String, double>>[];

      // Tìm cặp số hợp lệ cho latitude, longitude
      for (int i = 0; i < allPreciseNumbers.length - 1; i++) {
        final lat = allPreciseNumbers[i];
        final lng = allPreciseNumbers[i + 1];

        if (_isValidCoordinate(lat, lng)) {
          validPairs.add({'latitude': lat, 'longitude': lng});
        }
      }

      // Thử reverse order (lng, lat)
      for (int i = 0; i < allPreciseNumbers.length - 1; i++) {
        final lng = allPreciseNumbers[i];
        final lat = allPreciseNumbers[i + 1];

        if (_isValidCoordinate(lat, lng)) {
          validPairs.add({'latitude': lat, 'longitude': lng});
        }
      }

      // Nếu có nhiều cặp hợp lệ, chọn cặp có vẻ thực tế nhất
      if (validPairs.isNotEmpty) {
        // Sắp xếp theo độ "thực tế" của coordinates
        validPairs.sort((a, b) {
          final scoreA = _calculateRealismScore(
            a['latitude']!,
            a['longitude']!,
          );
          final scoreB = _calculateRealismScore(
            b['latitude']!,
            b['longitude']!,
          );
          return scoreB.compareTo(scoreA); // Sắp xếp từ cao đến thấp
        });

        final bestPair = validPairs.first;
        return bestPair;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Tính điểm "thực tế" của coordinates
  static double _calculateRealismScore(double lat, double lng) {
    double score = 0.0;

    // Điểm cho độ chính xác (nhiều chữ số thập phân = cao hơn)
    final latDecimalPlaces = _countDecimalPlaces(lat);
    final lngDecimalPlaces = _countDecimalPlaces(lng);
    score += (latDecimalPlaces + lngDecimalPlaces) * 10;

    // Điểm cho vị trí gần các khu vực có người ở
    if (_isNearPopulatedArea(lat, lng)) {
      score += 100;
    }

    // Trừ điểm cho các giá trị quá đơn giản
    if (_isSimpleTestValue(lat) || _isSimpleTestValue(lng)) {
      score -= 200;
    }

    // Trừ điểm cho coordinates trong ocean
    if (_isInLargeOceanArea(lat, lng)) {
      score -= 150;
    }

    // Điểm cho coordinates trong phạm vi hợp lý cho Google Maps
    if (lat.abs() < 85 && lng.abs() < 180) {
      score += 20;
    }

    return score;
  }

  // Đếm số chữ số thập phân
  static int _countDecimalPlaces(double value) {
    final str = value.toString();
    if (!str.contains('.')) return 0;

    final parts = str.split('.');
    if (parts.length != 2) return 0;

    // Loại bỏ các số 0 cuối
    final decimalPart = parts[1].replaceAll(RegExp(r'0+$'), '');
    return decimalPart.length;
  }

  // Kiểm tra xem có gần khu vực có dân cư không
  static bool _isNearPopulatedArea(double lat, double lng) {
    // Danh sách các khu vực có dân cư chính (continents/major regions)
    final populatedRegions = [
      // North America
      {'minLat': 25.0, 'maxLat': 70.0, 'minLng': -180.0, 'maxLng': -50.0},
      // South America
      {'minLat': -55.0, 'maxLat': 15.0, 'minLng': -85.0, 'maxLng': -35.0},
      // Europe
      {'minLat': 35.0, 'maxLat': 75.0, 'minLng': -10.0, 'maxLng': 45.0},
      // Africa
      {'minLat': -35.0, 'maxLat': 40.0, 'minLng': -20.0, 'maxLng': 55.0},
      // Asia
      {'minLat': 5.0, 'maxLat': 80.0, 'minLng': 25.0, 'maxLng': 180.0},
      // Oceania
      {'minLat': -50.0, 'maxLat': -5.0, 'minLng': 110.0, 'maxLng': 180.0},
    ];

    for (final region in populatedRegions) {
      if (lat >= region['minLat']! &&
          lat <= region['maxLat']! &&
          lng >= region['minLng']! &&
          lng <= region['maxLng']!) {
        return true;
      }
    }

    return false;
  }

  // Extract coordinates từ data attributes
  static Map<String, double>? _extractCoordsFromDataAttributes(String html) {
    try {
      final RegExp dataPattern = RegExp(
        r'data-[^=]*(?:lat|latitude)[^=]*=["\x27]([^"\x27]+)["\x27][^>]*data-[^=]*(?:lng|longitude)[^=]*=["\x27]([^"\x27]+)["\x27]',
        caseSensitive: false,
      );

      final match = dataPattern.firstMatch(html);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);

        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Extract coordinates từ JSON-LD structured data
  static Map<String, double>? _extractCoordsFromJsonLd(String html) {
    try {
      final RegExp jsonLdPattern = RegExp(
        r'<script[^>]*type=["\x27]application/ld\+json["\x27][^>]*>(.*?)</script>',
        caseSensitive: false,
        dotAll: true,
      );

      final matches = jsonLdPattern.allMatches(html);
      for (final match in matches) {
        try {
          final jsonString = match.group(1)!;
          final jsonData = json.decode(jsonString);

          final coords = _extractCoordsFromJson(jsonData);
          if (coords != null) {
            return coords;
          }
        } catch (e) {
          continue; // Skip invalid JSON
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Helper để extract coordinates từ JSON object
  static Map<String, double>? _extractCoordsFromJson(dynamic json) {
    if (json is Map) {
      // Tìm geo coordinates
      if (json['geo'] != null) {
        final geo = json['geo'];
        if (geo is Map && geo['latitude'] != null && geo['longitude'] != null) {
          final lat = _parseNumeric(geo['latitude']);
          final lng = _parseNumeric(geo['longitude']);
          if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
            return {'latitude': lat, 'longitude': lng};
          }
        }
      }

      // Tìm address coordinates
      if (json['address'] != null && json['address']['geo'] != null) {
        return _extractCoordsFromJson(json['address']['geo']);
      }

      // Recursive search trong nested objects
      for (final value in json.values) {
        final result = _extractCoordsFromJson(value);
        if (result != null) return result;
      }
    } else if (json is List) {
      for (final item in json) {
        final result = _extractCoordsFromJson(item);
        if (result != null) return result;
      }
    }

    return null;
  }

  // Helper để parse số từ dynamic value
  static double? _parseNumeric(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  // Thử với Google Maps Embed API
  static Future<Map<String, double>?> _tryGoogleMapsEmbed(
    String shortUrl,
  ) async {
    try {
      // Placeholder for future implementation
      // This could involve extracting place_id from the URL and using Google Places API
      return null;
    } catch (e) {
      return null;
    }
  }

  // Parse Geo URI (geo:latitude,longitude)
  static Map<String, double>? _parseGeoUri(String text) {
    try {
      final RegExp geoRegex = RegExp(r'geo:(-?\d+\.?\d*),(-?\d+\.?\d*)');
      final match = geoRegex.firstMatch(text);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Parse Plus Code (Google's Open Location Code)
  static Future<Map<String, double>?> _parsePlusCode(String text) async {
    try {
      final RegExp plusCodeRegex = RegExp(
        r'\b[23456789CFGHJMPQRVWX]{8}\+[23456789CFGHJMPQRVWX]{2,3}\b',
      );
      final match = plusCodeRegex.firstMatch(text);
      if (match != null) {
        final plusCode = match.group(0)!;

        // Sử dụng Google Geocoding API để decode plus code
        final url =
            'https://maps.googleapis.com/maps/api/geocode/json?address=$plusCode&key=${AppConfig.googleMapsApiKey}';
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['results'] != null && data['results'].isNotEmpty) {
            final location = data['results'][0]['geometry']['location'];
            final lat = location['lat']?.toDouble();
            final lng = location['lng']?.toDouble();

            if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
              return {'latitude': lat, 'longitude': lng};
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Trích xuất tọa độ từ text dài
  static Map<String, double>? _extractCoordinatesFromText(String text) {
    try {
      // Pattern để tìm tọa độ trong text dài - cải thiện để bao gồm nhiều format hơn
      final List<RegExp> coordPatterns = [
        // Ưu tiên pattern có độ chính xác cao (nhiều chữ số thập phân)
        RegExp(
          r'(-?\d{1,3}\.\d{4,}),\s*(-?\d{1,3}\.\d{4,})',
        ), // High precision: 21.02851,105.85421
        RegExp(
          r'(-?\d{1,3}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})',
        ), // Medium precision
        RegExp(
          r'(-?\d{1,3}\.\d{2,}),\s*(-?\d{1,3}\.\d{2,})',
        ), // Standard precision
        // Named patterns với validation tốt hơn
        RegExp(
          r'lat[itude]*\s*[:=]\s*(-?\d+\.?\d*)\s*.*\s*lng|lon[gitude]*\s*[:=]\s*(-?\d+\.?\d*)',
          caseSensitive: false,
        ),
        RegExp(
          r'lat[itude]*\s*[:=]\s*(-?\d+\.?\d*)\s*,\s*lng|lon[gitude]*\s*[:=]\s*(-?\d+\.?\d*)',
          caseSensitive: false,
        ),

        // Basic patterns - nhưng với validation tốt hơn
        RegExp(r'(-?\d+\.?\d*),\s*(-?\d+\.?\d*)'), // Basic: 21.0285,105.8542
      ];

      // Tìm tất cả matches và chọn cái tốt nhất
      final validMatches = <Map<String, double>>[];

      for (final pattern in coordPatterns) {
        final matches = pattern.allMatches(text);
        for (final match in matches) {
          final lat = double.tryParse(match.group(1)!);
          final lng = double.tryParse(match.group(2)!);

          if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
            validMatches.add({'latitude': lat, 'longitude': lng});
          }
        }
      }

      if (validMatches.isNotEmpty) {
        // Sắp xếp theo độ chính xác và realism score
        validMatches.sort((a, b) {
          final scoreA = _calculateRealismScore(
            a['latitude']!,
            a['longitude']!,
          );
          final scoreB = _calculateRealismScore(
            b['latitude']!,
            b['longitude']!,
          );
          return scoreB.compareTo(scoreA);
        });

        return validMatches.first;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Kiểm tra tọa độ hợp lệ với logging chi tiết
  static bool _isValidCoordinate(double latitude, double longitude) {
    print('Validating coordinates: lat=$latitude, lng=$longitude');

    // Kiểm tra phạm vi cơ bản
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      print('Invalid range: lat must be -90 to 90, lng must be -180 to 180');
      return false;
    }

    // Kiểm tra tọa độ không được là giá trị không hợp lý
    if (latitude.isNaN ||
        longitude.isNaN ||
        latitude.isInfinite ||
        longitude.isInfinite) {
      print('Invalid values: NaN or Infinite coordinates');
      return false;
    }

    // Loại bỏ các giá trị test/placeholder phổ biến (chỉ giữ những cái rõ ràng là test)
    final List<List<double>> invalidCoords = [
      [0.0, 0.0], // Origin point
      [1.0, 1.0], // Test values
      [2.0, 2.0], // Test values
      [10.0, 10.0], // Common test values
      [123.456, 789.012], // Obviously fake values
      [12.345, 67.890], // Pattern-like test values
      [11.111, 22.222], // Repeating digits
      [55.555, 66.666], // Repeating digits
      [99.999, 88.888], // Repeating digits
      [37.7749, -122.4194], // San Francisco (common test location)
      [40.7128, -74.0060], // New York (common test location)
      [51.5074, -0.1278], // London (common test location)
      // Đã bỏ các tọa độ Việt Nam để không reject nhầm
    ];

    // Kiểm tra exact match với invalid coordinates
    for (final invalidCoord in invalidCoords) {
      if ((latitude - invalidCoord[0]).abs() < 0.000001 &&
          (longitude - invalidCoord[1]).abs() < 0.000001) {
        print('Rejected: Matches invalid test coordinate ${invalidCoord}');
        return false;
      }
    }

    // Loại bỏ coordinates có giá trị quá đơn giản (ít chữ số thập phân)
    if (_isSimpleTestValue(latitude) && _isSimpleTestValue(longitude)) {
      print('Rejected: Both coordinates are simple test values');
      return false;
    }

    // Loại bỏ coordinates trong vùng ocean rộng lớn (có thể là test data)
    if (_isInLargeOceanArea(latitude, longitude)) {
      print('Rejected: Located in large ocean area (likely test data)');
      return false;
    }

    // Kiểm tra thêm - nếu cả hai coordinates đều là số nguyên đơn giản
    if (latitude == latitude.round() &&
        longitude == longitude.round() &&
        latitude.abs() <= 10 &&
        longitude.abs() <= 10) {
      print('Rejected: Both coordinates are simple integers <= 10');
      return false;
    }

    // Kiểm tra pattern tọa độ có vẻ giả (độ chính xác quá cao nhưng không hợp lý)
    if (_isSuspiciousCoordinate(latitude, longitude)) {
      print('Rejected: Suspicious coordinate pattern detected');
      return false;
    }

    // Kiểm tra độ chính xác tọa độ - reject nếu có một trong hai tọa độ thiếu thập phân
    final latStr = latitude.toString();
    final lngStr = longitude.toString();

    // Nếu một trong hai không có phần thập phân hoặc chỉ có 1-2 chữ số thập phân
    if (!latStr.contains('.') || !lngStr.contains('.')) {
      print('Rejected: One coordinate lacks decimal places');
      return false;
    }

    final latDecimals = latStr.split('.')[1].length;
    final lngDecimals = lngStr.split('.')[1].length;

    // Cần ít nhất 2 chữ số thập phân cho tọa độ thực tế (giảm từ 3 xuống 2)
    if (latDecimals < 2 || lngDecimals < 2) {
      print(
        'Rejected: Insufficient decimal precision (lat:$latDecimals, lng:$lngDecimals)',
      );
      return false;
    }

    print('Coordinates validated successfully');
    return true;
  }

  // Kiểm tra tọa độ có vẻ đáng nghi không (logic đã được tối ưu)
  static bool _isSuspiciousCoordinate(double latitude, double longitude) {
    final latStr = latitude.toString();
    final lngStr = longitude.toString();

    // Chỉ reject những pattern rõ ràng là fake/test data
    // Pattern 1: Quá nhiều số 0 liên tiếp (4+ số 0)
    if (latStr.contains('0000') || lngStr.contains('0000')) {
      return true;
    }

    // Pattern 2: Cả hai tọa độ đều có cùng pattern số lặp lại rõ ràng
    if (_hasObviousRepeatingPattern(latStr) &&
        _hasObviousRepeatingPattern(lngStr)) {
      return true;
    }

    // Pattern 3: Tọa độ có pattern 123.123, 456.456, etc.
    if (_hasSequentialPattern(latStr) && _hasSequentialPattern(lngStr)) {
      return true;
    }

    return false; // Không reject các tọa độ bình thường
  }

  // Kiểm tra pattern số lặp lại rõ ràng (như 111.111, 222.222)
  static bool _hasObviousRepeatingPattern(String coordStr) {
    // Chỉ check pattern thật sự rõ ràng như 111.111, 222.222
    final RegExp obviousPattern = RegExp(r'^(\d)\1+\.?\1*$');
    return obviousPattern.hasMatch(coordStr);
  }

  // Kiểm tra pattern tuần tự (như 123.456, 789.012)
  static bool _hasSequentialPattern(String coordStr) {
    if (!coordStr.contains('.')) return false;

    final parts = coordStr.split('.');
    final integerPart = parts[0].replaceAll('-', '');
    final decimalPart = parts[1];

    // Chỉ check pattern tuần tự rõ ràng như 123, 456, 789
    return _isSequential(integerPart) && _isSequential(decimalPart);
  }

  // Kiểm tra chuỗi số có tuần tự không
  static bool _isSequential(String numStr) {
    if (numStr.length < 3) return false;

    for (int i = 0; i < numStr.length - 2; i++) {
      final curr = int.tryParse(numStr[i]);
      final next1 = int.tryParse(numStr[i + 1]);
      final next2 = int.tryParse(numStr[i + 2]);

      if (curr != null && next1 != null && next2 != null) {
        if (next1 == curr + 1 && next2 == curr + 2) {
          return true; // Tìm thấy pattern tuần tự
        }
      }
    }
    return false;
  }

  // Kiểm tra xem có phải giá trị test đơn giản không
  static bool _isSimpleTestValue(double value) {
    // Các số quá đơn giản như 1.0, 2.0, 10.0, etc.
    final String valueStr = value.toString();

    // Nếu chỉ có 1-2 chữ số và kết thúc bằng .0
    if (RegExp(r'^\d{1,2}\.0$').hasMatch(valueStr)) {
      return true;
    }

    // Nếu là số nguyên nhỏ
    if (value == value.round() && value.abs() <= 100 && value != 0) {
      return true;
    }

    return false;
  }

  // Kiểm tra xem có trong vùng ocean rộng lớn không
  static bool _isInLargeOceanArea(double latitude, double longitude) {
    // Tránh các vùng ocean rộng lớn có thể chứa test data
    // Pacific Ocean trung tâm
    if (latitude > -30 &&
        latitude < 30 &&
        longitude > -180 &&
        longitude < -120) {
      return true;
    }

    // Atlantic Ocean trung tâm
    if (latitude > -30 && latitude < 30 && longitude > -60 && longitude < 20) {
      return true;
    }

    // Null Island area (0,0)
    if (latitude.abs() < 1 && longitude.abs() < 1) {
      return true;
    }

    return false;
  }

  // Mở Google Maps với tọa độ
  static Future<void> openGoogleMaps(
    double latitude,
    double longitude, {
    String? label,
  }) async {
    try {
      final String url = label != null
          ? 'https://maps.google.com/maps?q=$latitude,$longitude($label)'
          : 'https://maps.google.com/maps?q=$latitude,$longitude';

      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch Google Maps';
      }
    } catch (e) {
      print('Error opening Google Maps: $e');
    }
  }

  // Chia sẻ vị trí
  static Future<void> shareLocation(
    double latitude,
    double longitude, {
    String? name,
  }) async {
    try {
      final String shareText = name != null
          ? '$name\nhttps://maps.google.com/maps?q=$latitude,$longitude'
          : 'https://maps.google.com/maps?q=$latitude,$longitude';

      await Clipboard.setData(ClipboardData(text: shareText));
    } catch (e) {
      print('Error sharing location: $e');
    }
  }

  // Lấy intent data từ Android
  static Future<Map<String, dynamic>?> getIntentData() async {
    try {
      final result = await _intentChannel.invokeMethod('getIntentData');
      if (result != null) {
        final data = Map<String, dynamic>.from(result);

        // Kiểm tra dữ liệu có hợp lệ không
        if (data.containsKey('data') && data['data'] != null) {
          final String locationText = data['data'].toString();

          // Chỉ trả về nếu dữ liệu thực sự có ý nghĩa
          if (locationText.trim().isNotEmpty &&
              locationText.trim().length > 5 &&
              _containsLocationData(locationText)) {
            return data;
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Xóa intent data
  static Future<void> clearIntentData() async {
    try {
      await _intentChannel.invokeMethod('clearIntentData');
      // Reset shared data state
      SharedDataState.reset();
      _pendingSharedData = null;
    } catch (e) {
      // Silent fail
    }
  }
}
