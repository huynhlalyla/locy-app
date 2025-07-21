import 'package:flutter/services.dart';

class SharedDataState {
  static bool _isProcessingSharedData = false;
  static DateTime? _lastProcessedTime;

  // Kiểm tra xem có đang process shared data không
  static bool get isProcessing => _isProcessingSharedData;

  // Set trạng thái processing
  static void setProcessing(bool processing) {
    _isProcessingSharedData = processing;
    if (processing) {
      _lastProcessedTime = DateTime.now();
    }
  }

  // Kiểm tra xem có vừa process gần đây không (trong 5 giây)
  static bool get wasRecentlyProcessed {
    if (_lastProcessedTime == null) return false;
    return DateTime.now().difference(_lastProcessedTime!) <
        Duration(seconds: 5);
  }

  // Clear clipboard để tránh process lại
  static Future<void> clearClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: ''));
    } catch (e) {
      // Ignore clipboard errors
    }
  }

  // Reset state
  static void reset() {
    _isProcessingSharedData = false;
    _lastProcessedTime = null;
  }
}
