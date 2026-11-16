/// App-wide settings. Change these before building the APK.
class AppConfig {
  AppConfig._();

  static const String appName = 'VeeVee Field Locator';

  /// Must match `version:` in pubspec.yaml (the part before `+`).
  static const String appVersion = '1.0.8';

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

  /// Customer (trial) builds: show only contacts created by the logged-in
  /// Odoo user, so the list starts empty. Switched on at build time with
  /// `--dart-define=OWN_CONTACTS_ONLY=true`; VeeVee's own build shows all.
  static const bool ownContactsOnly = bool.fromEnvironment('OWN_CONTACTS_ONLY');

  static const String supportPhone = '+91 99657 82269';
  static const String supportEmail = 'info@veeveeinfotech.com';
}
