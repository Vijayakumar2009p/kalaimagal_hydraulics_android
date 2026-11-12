/// App-wide settings. Change these before building the APK.
class AppConfig {
  AppConfig._();

  static const String appName = 'VeeVee Field Locator';

  /// Must match `version:` in pubspec.yaml (the part before `+`).
  static const String appVersion = '1.0.6';

  /// Pre-filled on the login screen (Advanced settings).
  static const String defaultServerUrl = 'https://www.veeveeinfotech.com';

  /// Pre-filled database name. Used when the server hides its database list.
  /// Replace with your real database name before building.
  static const String defaultDatabase = '';

  /// A location is "good" when GPS accuracy is this many metres or better.
  static const double goodAccuracyMeters = 20;

  /// Network timeout for each Odoo request.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Retry pending entries this often while the app is open.
  static const Duration autoSyncInterval = Duration(minutes: 1);

  static const String userAgent =
      'VeeVeeFieldLocator/$appVersion (com.veeveeinfotech.fieldlocator; info@veeveeinfotech.com)';

  /// Contacts shown in the app: companies and individual contacts.
  /// Left out: invoice/delivery child addresses and your own staff (Odoo users).
  static const List<dynamic> customerDomain = [
    '&',
    '!',
    ['user_ids.share', '=', false],
    '|',
    ['is_company', '=', true],
    ['type', '=', 'contact'],
  ];

  static const String supportPhone = '+91 99657 82269';
  static const String supportEmail = 'info@veeveeinfotech.com';
}
