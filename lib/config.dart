class AppConfig {
  /// Public desk. A phone with internet tries this first.
  static const baseUrl = 'https://bacolodlife.org';

  /// This laptop on the current Wi-Fi (Converge). A real phone uses this
  /// when the public desk is down or the officer account only exists locally.
  static const localBaseUrl = 'http://192.168.100.2/BITCAS_UI_Skeleton';

  /// Android emulator loopback to XAMPP on this laptop. A real phone cannot use it.
  static const emulatorBaseUrl = 'http://10.0.2.2/BITCAS_UI_Skeleton';
}
