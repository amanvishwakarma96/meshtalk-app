import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/security/device_agreement_identity.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';

class RoomJoinRequest {
  RoomJoinRequest({
    required this.deviceId,
    required this.signingKeyId,
    required Uint8List signingPublicKeyBytes,
    required this.agreementKeyId,
    required Uint8List agreementPublicKeyBytes,
    required this.createdAtUtc,
    required Uint8List signatureBytes,
  })  : signingPublicKeyBytes = Uint8List.fromList(signingPublicKeyBytes),
        agreementPublicKeyBytes = Uint8List.fromList(agreementPublicKeyBytes),
        signatureBytes = Uint8List.fromList(signatureBytes) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty.');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(signingKeyId) ||
        !RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(agreementKeyId)) {
      throw ArgumentError('Join request contains an invalid key identifier.');
    }
    if (this.signingPublicKeyBytes.length != 32 ||
        this.agreementPublicKeyBytes.length != 32) {
      throw ArgumentError('Join request public keys must contain 32 bytes.');
    }
    if (this.signatureBytes.length != 64) {
      throw ArgumentError('Join request signature must contain 64 bytes.');
    }
  }

  final String deviceId;
  final String signingKeyId;
  final Uint8List signingPublicKeyBytes;
  final String agreementKeyId;
  final Uint8List agreementPublicKeyBytes;
  final DateTime createdAtUtc;
  final Uint8List signatureBytes;

  Map<String, Object> get signedFields => <String, Object>{
        'agreementKeyId': agreementKeyId,
        'agreementPublicKey': base64UrlEncode(agreementPublicKeyBytes),
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'signingKeyId': signingKeyId,
        'signingPublicKey': base64UrlEncode(signingPublicKeyBytes),
        'version': 1,
      };

  Map<String, Object> toJson() => <String, Object>{
        ...signedFields,
        'signature': base64UrlEncode(signatureBytes),
      };
}

class RoomJoinRequestCodec {
  RoomJoinRequestCodec({
    Ed25519? signatureAlgorithm,
    HashAlgorithm? hashAlgorithm,
  })  : _signatureAlgorithm = signatureAlgorithm ?? Ed25519(),
        _hashAlgorithm = hashAlgorithm ?? Sha256();

  static const String _prefix = 'MTJ1';
  final Ed25519 _signatureAlgorithm;
  final HashAlgorithm _hashAlgorithm;

  Future<RoomJoinRequest> issue({
    required DeviceIdentity signingIdentity,
    required DeviceAgreementIdentity agreementIdentity,
    DateTime? createdAtUtc,
  }) async {
    if (signingIdentity.deviceId != agreementIdentity.deviceId) {
      throw ArgumentError(
          'Signing and agreement identities must share a device ID.');
    }
    final requestFields = <String, Object>{
      'agreementKeyId': agreementIdentity.keyId,
      'agreementPublicKey': base64UrlEncode(agreementIdentity.publicKeyBytes),
      'createdAtUtc':
          (createdAtUtc ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
      'deviceId': signingIdentity.deviceId,
      'signingKeyId': signingIdentity.keyId,
      'signingPublicKey': base64UrlEncode(signingIdentity.publicKeyBytes),
      'version': 1,
    };
    final signature = await _signatureAlgorithm.sign(
      _canonicalBytes(requestFields),
      keyPair: SimpleKeyPairData(
        signingIdentity.privateKeyBytes,
        publicKey: SimplePublicKey(
          signingIdentity.publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
        type: KeyPairType.ed25519,
      ),
    );
    return RoomJoinRequest(
      deviceId: signingIdentity.deviceId,
      signingKeyId: signingIdentity.keyId,
      signingPublicKeyBytes: signingIdentity.publicKeyBytes,
      agreementKeyId: agreementIdentity.keyId,
      agreementPublicKeyBytes: agreementIdentity.publicKeyBytes,
      createdAtUtc: DateTime.parse(requestFields['createdAtUtc']! as String),
      signatureBytes: Uint8List.fromList(signature.bytes),
    );
  }

  Future<bool> verify(RoomJoinRequest request) async {
    final signingKeyId = await _deriveKeyId(request.signingPublicKeyBytes);
    final agreementKeyId = await _deriveKeyId(request.agreementPublicKeyBytes);
    if (signingKeyId != request.signingKeyId ||
        agreementKeyId != request.agreementKeyId) {
      return false;
    }
    return _signatureAlgorithm.verify(
      _canonicalBytes(request.signedFields),
      signature: Signature(
        request.signatureBytes,
        publicKey: SimplePublicKey(
          request.signingPublicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  String encode(RoomJoinRequest request) {
    final payload = base64UrlEncode(utf8.encode(jsonEncode(request.toJson())))
        .replaceAll('=', '');
    return '$_prefix.$payload';
  }

  RoomJoinRequest decode(String rawCode) {
    final code = rawCode.trim();
    final parts = code.split('.');
    if (parts.length != 2 || parts[0] != _prefix) {
      throw const FormatException('Join request has an invalid format.');
    }
    try {
      final raw = jsonDecode(utf8.decode(_decodeBase64Url(parts[1])));
      if (raw is! Map<String, dynamic> || raw['version'] != 1) {
        throw const FormatException('Unsupported join request version.');
      }
      return RoomJoinRequest(
        deviceId: raw['deviceId'] as String,
        signingKeyId: raw['signingKeyId'] as String,
        signingPublicKeyBytes: Uint8List.fromList(
          base64Url.decode(raw['signingPublicKey'] as String),
        ),
        agreementKeyId: raw['agreementKeyId'] as String,
        agreementPublicKeyBytes: Uint8List.fromList(
          base64Url.decode(raw['agreementPublicKey'] as String),
        ),
        createdAtUtc: DateTime.parse(raw['createdAtUtc'] as String).toUtc(),
        signatureBytes: Uint8List.fromList(
          base64Url.decode(raw['signature'] as String),
        ),
      );
    } on Object catch (error) {
      throw FormatException('Join request is malformed: $error');
    }
  }

  Future<String> _deriveKeyId(List<int> publicKeyBytes) async {
    final digest = await _hashAlgorithm.hash(publicKeyBytes);
    return base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', '');
  }

  Uint8List _canonicalBytes(Map<String, Object> fields) {
    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = <String, Object>{
      for (final key in keys) key: fields[key]!,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(canonical)));
  }

  List<int> _decodeBase64Url(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
  }
}
