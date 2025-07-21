class AppConfig {
  // Google Maps API Key
  static const String googleMapsApiKey =
      'AIzaSyDQ6akn3yVRU_pyFH8Q3zUgcVEhLTPgT3E';

  // App Settings
  static const String appName = 'Locy';
  static const String appVersion = '1.0.0';

  // Database Settings
  static const String databaseName = 'locy_database.db';
  static const int databaseVersion = 1;

  // Location Settings
  static const double defaultLatitude = 21.0285; // Hanoi
  static const double defaultLongitude = 105.8542; // Hanoi
  static const double defaultZoom = 15.0;

  // Shared Preferences Keys
  static const String keyFirstLaunch = 'first_launch';
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';

  // Intent and Sharing - Updated to use correct package name
  static const String intentChannelName = 'com.example.locyapp/intent';
  static const String locationReceiverChannelName =
      'com.example.locyapp/location_receiver';
}
