import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfilePreferences {
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
}

class SharedPreferencesProfilePreferences implements ProfilePreferences {
  SharedPreferencesProfilePreferences({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> readString(String key) => _preferences.getString(key);

  @override
  Future<void> writeString(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

class ProfileStore {
  ProfileStore({
    required ProfilePreferences preferences,
    Uuid? uuid,
  })  : _preferences = preferences,
        _uuid = uuid ?? Uuid();

  static const String _deviceIdKey = 'profile.device_id';
  static const String _displayNameKey = 'profile.display_name';

  final ProfilePreferences _preferences;
  final Uuid _uuid;

  Future<LocalProfile> loadOrCreate() async {
    var deviceId = await _preferences.readString(_deviceIdKey);
    if (deviceId == null || deviceId.trim().isEmpty) {
      deviceId = _uuid.v4();
      await _preferences.writeString(_deviceIdKey, deviceId);
    }

    var displayName = await _preferences.readString(_displayNameKey);
    if (displayName == null || displayName.trim().isEmpty) {
      displayName = 'Mesh ${deviceId.substring(0, 4).toUpperCase()}';
      await _preferences.writeString(_displayNameKey, displayName);
    }

    return LocalProfile(
      deviceId: deviceId,
      displayName: displayName,
    );
  }
}
