import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app settings (spec §5: "Location metadata: ON/OFF",
/// "Require location: ON/OFF", plus upload/network configuration).
class SettingsService {
  SettingsService._(this._prefs);
  final SharedPreferences _prefs;

  static SettingsService? _instance;

  static Future<SettingsService> instance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = SettingsService._(prefs);
    return _instance!;
  }

  static const _kLocationEnabled = 'location_metadata_enabled';
  static const _kRequireLocation = 'require_location';
  static const _kMaxLocationAgeSec = 'max_location_age_seconds';
  static const _kServerUrl = 'server_base_url';
  static const _kConnectTimeoutSec = 'connect_timeout_seconds';
  static const _kSendTimeoutSec = 'send_timeout_seconds';
  static const _kReceiveTimeoutSec = 'receive_timeout_seconds';
  static const _kMaxRetries = 'max_upload_retries';
  static const _kApiToken = 'api_token';

  bool get locationMetadataEnabled => _prefs.getBool(_kLocationEnabled) ?? true;
  Future<void> setLocationMetadataEnabled(bool v) => _prefs.setBool(_kLocationEnabled, v);

  bool get requireLocation => _prefs.getBool(_kRequireLocation) ?? false;
  Future<void> setRequireLocation(bool v) => _prefs.setBool(_kRequireLocation, v);

  int get maxLocationAgeSeconds => _prefs.getInt(_kMaxLocationAgeSec) ?? 30;
  Future<void> setMaxLocationAgeSeconds(int v) => _prefs.setInt(_kMaxLocationAgeSec, v);

  // Default targets the Node server started with `npm start`, reachable
  // from an emulator via 10.0.2.2 (Android) or localhost (iOS simulator).
  // A physical device needs the machine's LAN IP — see the README.
  String get serverBaseUrl => _prefs.getString(_kServerUrl) ?? 'http://10.0.2.2:3000';
  Future<void> setServerBaseUrl(String v) => _prefs.setString(_kServerUrl, v);

  int get connectTimeoutSeconds => _prefs.getInt(_kConnectTimeoutSec) ?? 10;
  Future<void> setConnectTimeoutSeconds(int v) => _prefs.setInt(_kConnectTimeoutSec, v);

  int get sendTimeoutSeconds => _prefs.getInt(_kSendTimeoutSec) ?? 60;
  Future<void> setSendTimeoutSeconds(int v) => _prefs.setInt(_kSendTimeoutSec, v);

  int get receiveTimeoutSeconds => _prefs.getInt(_kReceiveTimeoutSec) ?? 60;
  Future<void> setReceiveTimeoutSeconds(int v) => _prefs.setInt(_kReceiveTimeoutSec, v);

  int get maxUploadRetries => _prefs.getInt(_kMaxRetries) ?? 3;
  Future<void> setMaxUploadRetries(int v) => _prefs.setInt(_kMaxRetries, v);

  String get apiToken => _prefs.getString(_kApiToken) ?? '';
  Future<void> setApiToken(String v) => _prefs.setString(_kApiToken, v);
}
