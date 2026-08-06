import 'dart:convert';
import 'dart:typed_data';

import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

enum IdentityTrustLevel {
  seen,
  verified,
}

enum IdentityTrustDecision {
  firstSeen,
  trustedSeen,
  trustedVerified,
  changed,
}

class TrustedIdentitySummary {
  const TrustedIdentitySummary({
    required this.deviceId,
    required this.keyId,
    required this.trustLevel,
    required this.firstSeenAtUtc,
    required this.lastSeenAtUtc,
    this.pendingKeyId,
    this.changedAtUtc,
  });

  final String deviceId;
  final String keyId;
  final IdentityTrustLevel trustLevel;
  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final String? pendingKeyId;
  final DateTime? changedAtUtc;

  String get fingerprint => identityFingerprint(keyId);
  String? get pendingFingerprint =>
      pendingKeyId == null ? null : identityFingerprint(pendingKeyId!);
  bool get hasPendingChange => pendingKeyId != null;
}

class IdentityTrustEvaluation {
  const IdentityTrustEvaluation({
    required this.decision,
    required this.identity,
  });

  final IdentityTrustDecision decision;
  final TrustedIdentitySummary identity;
}

class IdentityTrustStore {
  IdentityTrustStore({
    required SecureValueStore values,
    DateTime Function()? nowUtc,
  })  : _values = values,
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static const String _storageKey = 'meshtalk.identity-trust.v1';
  static const int _maximumIdentities = 256;

  final SecureValueStore _values;
  final DateTime Function() _nowUtc;

  Future<IdentityTrustEvaluation> evaluate({
    required String senderId,
    required String keyId,
    required Uint8List publicKeyBytes,
  }) async {
    final state = await _readState();
    final now = _nowUtc();
    final existing = state.byDeviceId(senderId);
    if (existing == null) {
      if (state.identities.length >= _maximumIdentities) {
        throw StateError('Trusted identity limit reached.');
      }
      final created = _TrustedIdentity(
        deviceId: senderId,
        keyId: keyId,
        publicKeyBytes: publicKeyBytes,
        trustLevel: IdentityTrustLevel.seen,
        firstSeenAtUtc: now,
        lastSeenAtUtc: now,
      );
      await _writeState(
        _IdentityTrustState(<_TrustedIdentity>[...state.identities, created]),
      );
      return IdentityTrustEvaluation(
        decision: IdentityTrustDecision.firstSeen,
        identity: created.summary,
      );
    }

    if (_constantTimeEquals(existing.publicKeyBytes, publicKeyBytes) &&
        existing.keyId == keyId) {
      final updated = existing.copyWith(lastSeenAtUtc: now);
      await _replace(state, updated);
      return IdentityTrustEvaluation(
        decision: updated.trustLevel == IdentityTrustLevel.verified
            ? IdentityTrustDecision.trustedVerified
            : IdentityTrustDecision.trustedSeen,
        identity: updated.summary,
      );
    }

    final changed = existing.copyWith(
      pendingKeyId: keyId,
      pendingPublicKeyBytes: publicKeyBytes,
      changedAtUtc: now,
      lastSeenAtUtc: now,
    );
    await _replace(state, changed);
    return IdentityTrustEvaluation(
      decision: IdentityTrustDecision.changed,
      identity: changed.summary,
    );
  }

  Future<List<TrustedIdentitySummary>> list() async {
    final state = await _readState();
    final values = state.identities
        .map((identity) => identity.summary)
        .toList(growable: false)
      ..sort(
          (left, right) => right.lastSeenAtUtc.compareTo(left.lastSeenAtUtc));
    return List<TrustedIdentitySummary>.unmodifiable(values);
  }

  Future<void> markVerified(String deviceId, String keyId) async {
    final state = await _readState();
    final identity = state.byDeviceId(deviceId);
    if (identity == null || identity.keyId != keyId) {
      throw StateError('The selected identity is no longer current.');
    }
    await _replace(
      state,
      identity.copyWith(trustLevel: IdentityTrustLevel.verified),
    );
  }

  Future<void> acceptPending(String deviceId, String pendingKeyId) async {
    final state = await _readState();
    final identity = state.byDeviceId(deviceId);
    if (identity == null ||
        identity.pendingKeyId != pendingKeyId ||
        identity.pendingPublicKeyBytes == null) {
      throw StateError('The pending identity change is no longer available.');
    }
    final now = _nowUtc();
    await _replace(
      state,
      _TrustedIdentity(
        deviceId: identity.deviceId,
        keyId: identity.pendingKeyId!,
        publicKeyBytes: identity.pendingPublicKeyBytes!,
        trustLevel: IdentityTrustLevel.seen,
        firstSeenAtUtc: now,
        lastSeenAtUtc: now,
      ),
    );
  }

  Future<void> rejectPending(String deviceId, String pendingKeyId) async {
    final state = await _readState();
    final identity = state.byDeviceId(deviceId);
    if (identity == null || identity.pendingKeyId != pendingKeyId) {
      return;
    }
    await _replace(
      state,
      identity.copyWith(clearPending: true),
    );
  }

  Future<void> _replace(
    _IdentityTrustState state,
    _TrustedIdentity replacement,
  ) async {
    final identities = state.identities
        .map(
          (identity) => identity.deviceId == replacement.deviceId
              ? replacement
              : identity,
        )
        .toList(growable: false);
    await _writeState(_IdentityTrustState(identities));
  }

  Future<_IdentityTrustState> _readState() async {
    final encoded = await _values.read(_storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const _IdentityTrustState(<_TrustedIdentity>[]);
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('Unsupported identity trust version.');
      }
      final rawIdentities = decoded['identities'];
      if (rawIdentities is! List<dynamic>) {
        throw const FormatException('Identity trust entries are malformed.');
      }
      final identities =
          rawIdentities.map(_identityFromJson).toList(growable: false);
      if (identities.length > _maximumIdentities) {
        throw const FormatException(
            'Identity trust storage exceeds its limit.');
      }
      return _IdentityTrustState(identities);
    } on FormatException catch (error) {
      throw StateError('Identity trust storage is corrupt: ${error.message}');
    } on Object catch (error) {
      throw StateError('Identity trust storage is corrupt: $error');
    }
  }

  _TrustedIdentity _identityFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Trusted identity must be an object.');
    }
    final deviceId = raw['deviceId'];
    final keyId = raw['keyId'];
    final publicKey = raw['publicKey'];
    final trustLevel = raw['trustLevel'];
    final firstSeenAtUtc = raw['firstSeenAtUtc'];
    final lastSeenAtUtc = raw['lastSeenAtUtc'];
    final pendingKeyId = raw['pendingKeyId'];
    final pendingPublicKey = raw['pendingPublicKey'];
    final changedAtUtc = raw['changedAtUtc'];
    if (deviceId is! String ||
        keyId is! String ||
        publicKey is! String ||
        trustLevel is! String ||
        firstSeenAtUtc is! String ||
        lastSeenAtUtc is! String) {
      throw const FormatException('Trusted identity fields are invalid.');
    }
    return _TrustedIdentity(
      deviceId: deviceId,
      keyId: keyId,
      publicKeyBytes: Uint8List.fromList(_decodeBase64Url(publicKey)),
      trustLevel: IdentityTrustLevel.values.byName(trustLevel),
      firstSeenAtUtc: DateTime.parse(firstSeenAtUtc).toUtc(),
      lastSeenAtUtc: DateTime.parse(lastSeenAtUtc).toUtc(),
      pendingKeyId: pendingKeyId is String ? pendingKeyId : null,
      pendingPublicKeyBytes: pendingPublicKey is String
          ? Uint8List.fromList(_decodeBase64Url(pendingPublicKey))
          : null,
      changedAtUtc:
          changedAtUtc is String ? DateTime.parse(changedAtUtc).toUtc() : null,
    );
  }

  Future<void> _writeState(_IdentityTrustState state) async {
    await _values.write(
      _storageKey,
      jsonEncode(<String, Object>{
        'version': 1,
        'identities': state.identities
            .map(
              (identity) => <String, Object?>{
                'deviceId': identity.deviceId,
                'keyId': identity.keyId,
                'publicKey': _base64UrlWithoutPadding(identity.publicKeyBytes),
                'trustLevel': identity.trustLevel.name,
                'firstSeenAtUtc':
                    identity.firstSeenAtUtc.toUtc().toIso8601String(),
                'lastSeenAtUtc':
                    identity.lastSeenAtUtc.toUtc().toIso8601String(),
                'pendingKeyId': identity.pendingKeyId,
                'pendingPublicKey': identity.pendingPublicKeyBytes == null
                    ? null
                    : _base64UrlWithoutPadding(
                        identity.pendingPublicKeyBytes!,
                      ),
                'changedAtUtc':
                    identity.changedAtUtc?.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
      }),
    );
  }

  String _base64UrlWithoutPadding(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  List<int> _decodeBase64Url(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

class _IdentityTrustState {
  const _IdentityTrustState(this.identities);

  final List<_TrustedIdentity> identities;

  _TrustedIdentity? byDeviceId(String deviceId) {
    for (final identity in identities) {
      if (identity.deviceId == deviceId) {
        return identity;
      }
    }
    return null;
  }
}

class _TrustedIdentity {
  _TrustedIdentity({
    required this.deviceId,
    required this.keyId,
    required Uint8List publicKeyBytes,
    required this.trustLevel,
    required this.firstSeenAtUtc,
    required this.lastSeenAtUtc,
    this.pendingKeyId,
    Uint8List? pendingPublicKeyBytes,
    this.changedAtUtc,
  })  : publicKeyBytes = Uint8List.fromList(publicKeyBytes),
        pendingPublicKeyBytes = pendingPublicKeyBytes == null
            ? null
            : Uint8List.fromList(pendingPublicKeyBytes) {
    if (this.publicKeyBytes.length != 32) {
      throw const FormatException('Trusted public key length is invalid.');
    }
    if (this.pendingPublicKeyBytes != null &&
        this.pendingPublicKeyBytes!.length != 32) {
      throw const FormatException('Pending public key length is invalid.');
    }
  }

  final String deviceId;
  final String keyId;
  final Uint8List publicKeyBytes;
  final IdentityTrustLevel trustLevel;
  final DateTime firstSeenAtUtc;
  final DateTime lastSeenAtUtc;
  final String? pendingKeyId;
  final Uint8List? pendingPublicKeyBytes;
  final DateTime? changedAtUtc;

  TrustedIdentitySummary get summary => TrustedIdentitySummary(
        deviceId: deviceId,
        keyId: keyId,
        trustLevel: trustLevel,
        firstSeenAtUtc: firstSeenAtUtc,
        lastSeenAtUtc: lastSeenAtUtc,
        pendingKeyId: pendingKeyId,
        changedAtUtc: changedAtUtc,
      );

  _TrustedIdentity copyWith({
    IdentityTrustLevel? trustLevel,
    DateTime? lastSeenAtUtc,
    String? pendingKeyId,
    Uint8List? pendingPublicKeyBytes,
    DateTime? changedAtUtc,
    bool clearPending = false,
  }) {
    return _TrustedIdentity(
      deviceId: deviceId,
      keyId: keyId,
      publicKeyBytes: publicKeyBytes,
      trustLevel: trustLevel ?? this.trustLevel,
      firstSeenAtUtc: firstSeenAtUtc,
      lastSeenAtUtc: lastSeenAtUtc ?? this.lastSeenAtUtc,
      pendingKeyId: clearPending ? null : pendingKeyId ?? this.pendingKeyId,
      pendingPublicKeyBytes: clearPending
          ? null
          : pendingPublicKeyBytes ?? this.pendingPublicKeyBytes,
      changedAtUtc: clearPending ? null : changedAtUtc ?? this.changedAtUtc,
    );
  }
}
