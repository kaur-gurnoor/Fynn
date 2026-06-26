import 'package:at_client/at_client.dart';

class AtService {
  static AtService? _instance;
  static AtService get instance => _instance ??= AtService._();
  AtService._();

  static const namespace = 'fynn';

  AtClient get _client => AtClientManager.getInstance().atClient;

  String get currentAtsign => _client.getCurrentAtSign() ?? '';

  Future<void> put(String keyName, String value) async {
    final key = AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedBy = currentAtsign;
    await _client.put(key, value);
  }

  Future<String?> get(String keyName) async {
    try {
      final key = AtKey()
        ..key = keyName
        ..namespace = namespace
        ..sharedBy = currentAtsign;
      final result = await _client.get(key);
      return result.value as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String keyName) async {
    final key = AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedBy = currentAtsign;
    await _client.delete(key);
  }

  Future<List<AtKey>> scan(String pattern) async {
    try {
      return await _client.getAtKeys(regex: pattern);
    } catch (_) {
      return [];
    }
  }
}
