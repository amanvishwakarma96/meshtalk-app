import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}
