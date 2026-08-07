import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/device_agreement_identity.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/identity_trust_store.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';
import 'package:meshtalk_app/core/security/room_membership_manager.dart';
import 'package:meshtalk_app/core/security/room_membership_store.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/features/chat/data/chat_session.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

import '../../../helpers/fake_ble_chat.dart';
import '../../../helpers/fake_message_store.dart';

void main() {
  late FakeBleRadio radio;
  late FakeChatTransport transport;
  late FakeVerifiableChatTransport fallbackTransport;
  late FakeMessageStore messageStore;
  late SecureRoom secureRoom;
  late SecureRoomStore secureRoomStore;
  late RoomMembershipStore membershipStore;
  late RoomMembershipManager membershipManager;
  late MessageProtector protector;
  late DeviceIdentity localIdentity;
  late DeviceIdentity remoteIdentity;
  late DeviceIdentity changedRemoteIdentity;
  late DeviceAgreementIdentity localAgreementIdentity;
  late DeviceAgreementIdentity remoteAgreementIdentity;
  late IdentityTrustStore trustStore;
  late ChatSession session;
  var settingsOpened = false;

  setUp(() async {
    radio = FakeBleRadio();
    transport = FakeChatTransport(radio);
    fallbackTransport = FakeVerifiableChatTransport(
      radio,
      transportId: 'android-nearby',
      forcedAvailability: false,
    );
    messageStore = FakeMessageStore();
    protector = MessageProtector();
    secureRoom = await _secureRoom();
    protectorForHelper = protector;
    secureRoomForHelper = secureRoom;
    localIdentity = await _identity(_profile.deviceId);
    remoteIdentity = await _identity('remote-device');
    changedRemoteIdentity = await _identity('remote-device');
    localAgreementIdentity = await _agreementIdentity(_profile.deviceId);
    remoteAgreementIdentity = await _agreementIdentity('remote-device');
    final secureValues = _MemorySecureValueStore();
    secureRoomStore = SecureRoomStore(values: secureValues);
    await secureRoomStore.installEpochKey(
      roomId: secureRoom.id,
      roomName: secureRoom.name,
      epoch: secureRoom.epoch,
      keyId: secureRoom.keyId,
      keyBytes: secureRoom.keyBytes,
      activatedAtUtc: secureRoom.keyActivatedAtUtc,
    );
    membershipStore = RoomMembershipStore(values: secureValues);
    membershipManager = RoomMembershipManager(
      roomStore: secureRoomStore,
      membershipStore: membershipStore,
      signingIdentity: localIdentity,
      agreementIdentity: localAgreementIdentity,
    );
    await membershipManager.ensureLocalMembership(secureRoom);
    await _authorizeMember(
      store: membershipStore,
      room: secureRoom,
      issuer: localIdentity,
      member: remoteIdentity,
      agreementIdentity: remoteAgreementIdentity,
    );
    trustStore = IdentityTrustStore(values: secureValues);
    settingsOpened = false;
    session = _session(
      radio: radio,
      transport: transport,
      fallback: fallbackTransport,
      store: messageStore,
      room: secureRoom,
      roomStore: secureRoomStore,
      membershipManager: membershipManager,
      protector: protector,
      localIdentity: localIdentity,
      trustStore: trustStore,
      openSettings: () async {
        settingsOpened = true;
      },
    );
  });

  tearDown(() async {
    await session.close();
    await transport.close();
    await fallbackTransport.close();
    await radio.close();
  });

  test(
    'persists a signed ciphertext and marks it sent after recovery',
    () async {
      await session.initialize();
      await session.send(' hello mesh ');

      expect(session.state.pendingCount, 1);
      expect(
        messageStore.messages.single.deliveryStatus,
        StoredDeliveryStatus.queued,
      );
      final queued = messageStore.messages.single.envelope;
      expect(protector.isSignedProtectedPayload(queued.payload), isTrue);
      expect(
        session.state.messages.single.identityStatus,
        MessageIdentityStatus.local,
      );

      transport.emitPeers(const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ]);
      await _drainEvents();

      expect(session.state.pendingCount, 0);
      expect(
        session.state.messages.single.deliveryStatus,
        ChatDeliveryStatus.sent,
      );
      final decrypted = await protector.unprotect(
        envelope: transport.sentMessages.single,
        room: secureRoom,
      );
      expect(utf8.decode(decrypted.clearText), 'hello mesh');
      expect(decrypted.senderIdentity?.keyId, localIdentity.keyId);
    },
  );

  test('migrates queued plaintext to signed protocol v2', () async {
    final queuedEnvelope = MessageEnvelope(
      id: '550e8400-e29b-41d4-a716-446655440001',
      senderId: _profile.deviceId,
      roomId: 'nearby',
      timestampUtc: DateTime.utc(2026, 8, 4, 9),
      hopLimit: 4,
      payload: Uint8List.fromList(utf8.encode('survive restart')),
    );
    await messageStore.upsert(
      StoredChatMessage(
        envelope: queuedEnvelope,
        senderLabel: _profile.displayName,
        direction: StoredMessageDirection.outgoing,
        deliveryStatus: StoredDeliveryStatus.queued,
      ),
    );

    await session.initialize();

    expect(session.state.messages.single.text, 'survive restart');
    expect(
      session.state.messages.single.protectionStatus,
      MessageProtectionStatus.legacyUnencrypted,
    );
    expect(
      session.state.messages.single.identityStatus,
      MessageIdentityStatus.legacyUnsigned,
    );
    final migrated = messageStore.messages.single.envelope;
    expect(migrated.roomId, secureRoom.id);
    expect(protector.isSignedProtectedPayload(migrated.payload), isTrue);

    transport.emitPeers(const <NearbyPeer>[
      NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
    ]);
    await _drainEvents();

    final sent = transport.sentMessages.single;
    final decrypted = await protector.unprotect(
      envelope: sent,
      room: secureRoom,
    );
    expect(utf8.decode(decrypted.clearText), 'survive restart');
    expect(decrypted.senderIdentity?.keyId, localIdentity.keyId);
  });

  test(
    'pins a first-seen signed identity and relays ciphertext once',
    () async {
      await session.initialize();
      transport.emitPeers(const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ]);
      await _drainEvents();
      final incoming = await _protectedEnvelope(
        id: '550e8400-e29b-41d4-a716-446655440010',
        identity: remoteIdentity,
        text: 'from peer',
        hopLimit: 2,
      );

      transport.emitIncoming(incoming);
      transport.emitIncoming(incoming);
      await _drainEvents();

      expect(session.state.messages.single.text, 'from peer');
      expect(
        session.state.messages.single.identityStatus,
        MessageIdentityStatus.seen,
      );
      expect(
        session.state.trustedIdentities.single.keyId,
        remoteIdentity.keyId,
      );
      expect(
        session.state.trustedIdentities.single.trustLevel,
        IdentityTrustLevel.seen,
      );
      expect(messageStore.messages.length, 1);
      expect(transport.sentMessages.single.hopLimit, 1);
    },
  );

  test('marks a pinned fingerprint verified for later messages', () async {
    await session.initialize();
    final first = await _protectedEnvelope(
      id: '550e8400-e29b-41d4-a716-446655440011',
      identity: remoteIdentity,
      text: 'first',
      hopLimit: 1,
    );
    transport.emitIncoming(first);
    await _drainEvents();

    await session.verifyIdentity(session.state.trustedIdentities.single);
    final second = await _protectedEnvelope(
      id: '550e8400-e29b-41d4-a716-446655440012',
      identity: remoteIdentity,
      text: 'verified',
      hopLimit: 1,
    );
    transport.emitIncoming(second);
    await _drainEvents();

    expect(session.state.messages.last.text, 'verified');
    expect(
      session.state.messages.last.identityStatus,
      MessageIdentityStatus.verified,
    );
    expect(
      session.state.trustedIdentities.single.trustLevel,
      IdentityTrustLevel.verified,
    );
  });

  test(
    'blocks an owner-authorized changed identity until trust is updated',
    () async {
      await session.initialize();
      transport.emitPeers(const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ]);
      await _drainEvents();
      transport.emitIncoming(
        await _protectedEnvelope(
          id: '550e8400-e29b-41d4-a716-446655440013',
          identity: remoteIdentity,
          text: 'original key',
          hopLimit: 1,
        ),
      );
      await _drainEvents();
      await _authorizeMember(
        store: membershipStore,
        room: secureRoom,
        issuer: localIdentity,
        member: changedRemoteIdentity,
        agreementIdentity: remoteAgreementIdentity,
      );

      final changed = await _protectedEnvelope(
        id: '550e8400-e29b-41d4-a716-446655440014',
        identity: changedRemoteIdentity,
        text: 'new key blocked',
        hopLimit: 2,
      );
      transport.emitIncoming(changed);
      await _drainEvents();

      expect(session.state.messages.length, 1);
      expect(session.state.pendingIdentityChanges.length, 1);
      expect(
        session.state.pendingIdentityChanges.single.pendingKeyId,
        changedRemoteIdentity.keyId,
      );
      expect(
        session.state.diagnostics?.lastError,
        contains('Identity changed'),
      );
      expect(transport.sentMessages.last.id, changed.id);
      expect(transport.sentMessages.last.hopLimit, 1);
    },
  );

  test(
    'accepting an owner-authorized changed fingerprint releases the message',
    () async {
      await session.initialize();
      transport.emitIncoming(
        await _protectedEnvelope(
          id: '550e8400-e29b-41d4-a716-446655440015',
          identity: remoteIdentity,
          text: 'old key',
          hopLimit: 1,
        ),
      );
      await _drainEvents();
      await _authorizeMember(
        store: membershipStore,
        room: secureRoom,
        issuer: localIdentity,
        member: changedRemoteIdentity,
        agreementIdentity: remoteAgreementIdentity,
      );
      transport.emitIncoming(
        await _protectedEnvelope(
          id: '550e8400-e29b-41d4-a716-446655440016',
          identity: changedRemoteIdentity,
          text: 'approved new key',
          hopLimit: 1,
        ),
      );
      await _drainEvents();

      await session.acceptIdentityChange(
        session.state.pendingIdentityChanges.single,
      );
      await _drainEvents();

      expect(session.state.messages.length, 2);
      expect(session.state.messages.last.text, 'approved new key');
      expect(
        session.state.messages.last.identityStatus,
        MessageIdentityStatus.seen,
      );
      expect(session.state.pendingIdentityChanges, isEmpty);
      expect(
        session.state.trustedIdentities.single.keyId,
        changedRemoteIdentity.keyId,
      );
    },
  );

  test(
    'rejecting an owner-authorized changed fingerprint keeps old trust',
    () async {
      await session.initialize();
      transport.emitIncoming(
        await _protectedEnvelope(
          id: '550e8400-e29b-41d4-a716-446655440017',
          identity: remoteIdentity,
          text: 'old key',
          hopLimit: 1,
        ),
      );
      await _drainEvents();
      await _authorizeMember(
        store: membershipStore,
        room: secureRoom,
        issuer: localIdentity,
        member: changedRemoteIdentity,
        agreementIdentity: remoteAgreementIdentity,
      );
      transport.emitIncoming(
        await _protectedEnvelope(
          id: '550e8400-e29b-41d4-a716-446655440018',
          identity: changedRemoteIdentity,
          text: 'rejected key',
          hopLimit: 1,
        ),
      );
      await _drainEvents();

      await session.rejectIdentityChange(
        session.state.pendingIdentityChanges.single,
      );

      expect(session.state.messages.length, 1);
      expect(session.state.pendingIdentityChanges, isEmpty);
      expect(session.state.trustedIdentities.single.keyId, remoteIdentity.keyId);
    },
  );

  test(
    'drops tampered signed ciphertext and records an identity error',
    () async {
      await session.initialize();
      final incoming = await _protectedEnvelope(
        id: '550e8400-e29b-41d4-a716-446655440019',
        identity: remoteIdentity,
        text: 'do not display',
        hopLimit: 1,
      );
      final changed = Uint8List.fromList(incoming.payload);
      changed[changed.length - 1] ^= 0x01;

      transport.emitIncoming(incoming.copyWith(payload: changed));
      await _drainEvents();

      expect(session.state.messages, isEmpty);
      expect(messageStore.messages, isEmpty);
      expect(
        session.state.diagnostics?.lastError,
        contains('signature is invalid'),
      );
    },
  );

  test(
    'relays signed ciphertext for another room without trusting it',
    () async {
      await session.initialize();
      transport.emitPeers(const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ]);
      await _drainEvents();
      final otherRoom = await _secureRoom(
        roomId: 'anotherSecureRoom1234567',
        keyOffset: 40,
      );
      final incoming = await _protectedEnvelope(
        id: '550e8400-e29b-41d4-a716-446655440020',
        identity: remoteIdentity,
        text: 'relay only',
        hopLimit: 2,
        room: otherRoom,
      );

      transport.emitIncoming(incoming);
      await _drainEvents();

      expect(session.state.messages, isEmpty);
      expect(session.state.trustedIdentities, isEmpty);
      expect(transport.sentMessages.single.id, incoming.id);
      expect(transport.sentMessages.single.hopLimit, 1);
    },
  );

  test('retains permission recovery and Android Nearby fallback', () async {
    radio.currentAvailability = BleRadioAvailability.unauthorized;
    await session.initialize();
    expect(session.state.status, ChatConnectionStatus.permissionDenied);
    await session.openSettings();
    expect(settingsOpened, isTrue);

    await session.close();
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    fallbackTransport.forcedAvailability = true;
    session = _session(
      radio: radio,
      transport: transport,
      fallback: fallbackTransport,
      store: messageStore,
      room: secureRoom,
      roomStore: secureRoomStore,
      membershipManager: membershipManager,
      protector: protector,
      localIdentity: localIdentity,
      trustStore: trustStore,
      openSettings: () async {},
    );
    await session.initialize();

    expect(session.state.activeTransportKind, TransportKind.localWifi);
    expect(
      session.state.statusMessage,
      contains('Android Nearby Connections'),
    );
  });

  test(
    'routes matching-code approval and reports identity diagnostics',
    () async {
      radio.currentAvailability = BleRadioAvailability.poweredOff;
      fallbackTransport.forcedAvailability = true;
      await session.initialize();
      const request = PeerVerificationRequest(
        transportId: 'android-nearby',
        endpointId: 'endpoint-a',
        peerId: 'peer-a',
        displayName: 'Peer A',
        authenticationToken: '4721',
        isIncomingConnection: true,
      );
      fallbackTransport.emitVerification(request);
      await _drainEvents();

      await session.approvePeer(request);
      await _drainEvents();

      expect(fallbackTransport.approvedEndpointIds, <String>['endpoint-a']);
      expect(session.state.localIdentity.keyId, localIdentity.keyId);
      expect(session.state.diagnostics?.activeTransportId, 'android-nearby');
      expect(session.state.hasCurrentMembership, isTrue);
      expect(session.state.isRoomOwner, isTrue);
      expect(session.state.roomMembers.length, 2);
    },
  );
}

const LocalProfile _profile = LocalProfile(
  deviceId: 'device-local',
  displayName: 'Trail Phone',
);

ChatSession _session({
  required FakeBleRadio radio,
  required FakeChatTransport transport,
  required FakeChatTransport fallback,
  required FakeMessageStore store,
  required SecureRoom room,
  required SecureRoomStore roomStore,
  required RoomMembershipManager membershipManager,
  required MessageProtector protector,
  required DeviceIdentity localIdentity,
  required IdentityTrustStore trustStore,
  required Future<void> Function() openSettings,
}) {
  return ChatSession(
    profile: _profile,
    secureRoom: room,
    deviceIdentity: localIdentity,
    identityTrustStore: trustStore,
    membershipManager: membershipManager,
    secureRoomStore: roomStore,
    messageProtector: protector,
    radio: radio,
    bleTransport: transport,
    transportManager: TransportManager(
      transports: <ChatTransport>[transport, fallback],
    ),
    messageStore: store,
    openAppSettings: openSettings,
  );
}

Future<SecureRoom> _secureRoom({
  String roomId = 'secureRoomIdentifier1234',
  int keyOffset = 0,
}) async {
  final key = Uint8List.fromList(
    List<int>.generate(32, (index) => (index + keyOffset) % 256),
  );
  final codec = SecureRoomCodeCodec();
  return SecureRoom(
    id: roomId,
    name: 'Family mesh',
    keyId: await codec.deriveKeyId(key),
    keyBytes: key,
    createdAtUtc: DateTime.utc(2026, 8, 5),
  );
}

Future<DeviceIdentity> _identity(String deviceId) async {
  final extracted = await (await Ed25519().newKeyPair()).extract();
  final digest = await Sha256().hash(extracted.publicKey.bytes);
  return DeviceIdentity(
    deviceId: deviceId,
    keyId: base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', ''),
    publicKeyBytes: Uint8List.fromList(extracted.publicKey.bytes),
    privateKeyBytes: Uint8List.fromList(extracted.bytes),
    createdAtUtc: DateTime.utc(2026, 8, 6),
  );
}

Future<DeviceAgreementIdentity> _agreementIdentity(String deviceId) async {
  final extracted = await (await X25519().newKeyPair()).extract();
  final digest = await Sha256().hash(extracted.publicKey.bytes);
  return DeviceAgreementIdentity(
    deviceId: deviceId,
    keyId: base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', ''),
    publicKeyBytes: Uint8List.fromList(extracted.publicKey.bytes),
    privateKeyBytes: Uint8List.fromList(extracted.bytes),
    createdAtUtc: DateTime.utc(2026, 8, 6),
  );
}

Future<void> _authorizeMember({
  required RoomMembershipStore store,
  required SecureRoom room,
  required DeviceIdentity issuer,
  required DeviceIdentity member,
  required DeviceAgreementIdentity agreementIdentity,
}) async {
  final membership = await RoomMembershipCodec().issue(
    roomId: room.id,
    epoch: room.epoch,
    memberDeviceId: member.deviceId,
    memberPublicKeyBytes: member.publicKeyBytes,
    memberAgreementPublicKeyBytes: agreementIdentity.publicKeyBytes,
    role: RoomMemberRole.member,
    issuedAtUtc: DateTime.utc(2026, 8, 6, 12),
    issuer: issuer,
  );
  await store.upsert(membership);
}

Future<MessageEnvelope> _protectedEnvelope({
  required String id,
  required DeviceIdentity identity,
  required String text,
  required int hopLimit,
  SecureRoom? room,
}) {
  final targetRoom = room ?? secureRoomForHelper;
  return protectorForHelper.protect(
    envelope: MessageEnvelope(
      id: id,
      senderId: identity.deviceId,
      roomId: targetRoom.id,
      timestampUtc: DateTime.utc(2026, 8, 5, 12),
      hopLimit: hopLimit,
      payload: Uint8List(0),
    ),
    clearText: Uint8List.fromList(utf8.encode(text)),
    room: targetRoom,
    identity: identity,
  );
}

late SecureRoom secureRoomForHelper;
late MessageProtector protectorForHelper;

Future<void> _drainEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
