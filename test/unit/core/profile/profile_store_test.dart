import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/profile/profile_store.dart';

void main() {
  test('creates and reuses a local device identity', () async {
    final preferences = FakeProfilePreferences();
    final store = ProfileStore(preferences: preferences);

    final first = await store.loadOrCreate();
    final second = await store.loadOrCreate();

    expect(first.deviceId, isNotEmpty);
    expect(first.displayName, startsWith('Mesh '));
    expect(second.deviceId, first.deviceId);
    expect(second.displayName, first.displayName);
    expect(preferences.values.length, 2);
  });

  test('preserves an existing display name', () async {
    final preferences = FakeProfilePreferences(
      <String, String>{
        'profile.device_id': '550e8400-e29b-41d4-a716-446655440000',
        'profile.display_name': 'Trail Phone',
      },
    );
    final store = ProfileStore(preferences: preferences);

    final profile = await store.loadOrCreate();

    expect(profile.deviceId, '550e8400-e29b-41d4-a716-446655440000');
    expect(profile.displayName, 'Trail Phone');
  });

  test('updates the display name without replacing the device id', () async {
    final preferences = FakeProfilePreferences(
      <String, String>{
        'profile.device_id': '550e8400-e29b-41d4-a716-446655440000',
        'profile.display_name': 'Trail Phone',
      },
    );
    final store = ProfileStore(preferences: preferences);

    final profile = await store.updateDisplayName('  Aman   Phone  ');

    expect(profile.deviceId, '550e8400-e29b-41d4-a716-446655440000');
    expect(profile.displayName, 'Aman Phone');
    expect(preferences.values['profile.display_name'], 'Aman Phone');
  });

  test('rejects display names outside the supported length', () async {
    final store = ProfileStore(preferences: FakeProfilePreferences());

    await expectLater(store.updateDisplayName('A'), throwsArgumentError);
    await expectLater(
      store.updateDisplayName('A' * 25),
      throwsArgumentError,
    );
  });
}

class FakeProfilePreferences implements ProfilePreferences {
  FakeProfilePreferences([Map<String, String>? initialValues])
      : values = <String, String>{...?initialValues};

  final Map<String, String> values;

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }
}
