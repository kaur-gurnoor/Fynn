import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _keyOpenAIKey = 'openai_api_key';

  static SettingsService? _instance;
  static SettingsService get instance => _instance ??= SettingsService._();
  SettingsService._();

  Future<String?> getOpenAIKey() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyOpenAIKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setOpenAIKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenAIKey, key.trim());
  }

  Future<void> clearOpenAIKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOpenAIKey);
  }
}
