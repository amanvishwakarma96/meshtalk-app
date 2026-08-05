import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/bluetooth_low_energy_mesh_radio.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/profile/profile_store.dart';
import 'package:meshtalk_app/core/storage/message_store.dart';
import 'package:meshtalk_app/core/storage/sqlite_message_store.dart';
import 'package:meshtalk_app/core/transport/android_nearby_transport.dart';
import 'package:meshtalk_app/core/transport/ble_transport.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/ios_multipeer_gateway.dart';
import 'package:meshtalk_app/core/transport/ios_multipeer_transport.dart';
import 'package:meshtalk_app/core/transport/nearby_connections_gateway.dart';
import 'package:meshtalk_app/core/transport/plugin_ios_multipeer_gateway.dart';
import 'package:meshtalk_app/core/transport/plugin_nearby_connections_gateway.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/features/chat/data/chat_session.dart';
import 'package:permission_handler/permission_handler.dart';

final profileStoreProvider = Provider<ProfileStore>((ref) {
  return ProfileStore(
    preferences: SharedPreferencesProfilePreferences(),
  );
});

final localProfileProvider = FutureProvider<LocalProfile>((ref) async {
  return ref.watch(profileStoreProvider).loadOrCreate();
});

final messageStoreProvider = Provider<MessageStore>((ref) {
  final store = SqliteMessageStore();
  ref.onDispose(() {
    unawaited(store.close());
  });
  return store;
});

typedef BleRadioFactory = BleMeshRadio Function(LocalProfile profile);

final bleRadioFactoryProvider = Provider<BleRadioFactory>((ref) {
  return (profile) {
    return BluetoothLowEnergyMeshRadio(
      localName: _advertisedName(profile.displayName),
    );
  };
});

final nearbyConnectionsGatewayProvider = Provider<NearbyConnectionsGateway>(
  (ref) => PluginNearbyConnectionsGateway(),
);

final iosMultipeerGatewayProvider = Provider<IosMultipeerGateway>(
  (ref) => PluginIosMultipeerGateway(),
);

final chatSessionProvider = FutureProvider<ChatSession>((ref) async {
  final profile = await ref.watch(localProfileProvider.future);
  final radio = ref.watch(bleRadioFactoryProvider)(profile);
  final bleTransport = BleTransport(radio: radio);
  final nearbyGateway = ref.watch(nearbyConnectionsGatewayProvider);
  final iosMultipeerGateway = ref.watch(iosMultipeerGatewayProvider);
  final transports = <ChatTransport>[bleTransport];
  if (nearbyGateway.isSupported) {
    transports.add(
      AndroidNearbyTransport(
        profile: profile,
        gateway: nearbyGateway,
      ),
    );
  }
  if (iosMultipeerGateway.isSupported) {
    transports.add(
      IosMultipeerTransport(
        profile: profile,
        gateway: iosMultipeerGateway,
      ),
    );
  }

  final transportManager = TransportManager(transports: transports);
  final session = ChatSession(
    profile: profile,
    radio: radio,
    bleTransport: bleTransport,
    transportManager: transportManager,
    messageStore: ref.watch(messageStoreProvider),
    openAppSettings: () async {
      await openAppSettings();
    },
  );

  ref.onDispose(() {
    unawaited(session.close());
  });
  await session.initialize();
  return session;
});

String _advertisedName(String displayName) {
  final normalized = displayName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  final value = normalized.isEmpty ? 'MeshTalk' : normalized;
  return value.length <= 20 ? value : value.substring(0, 20);
}
