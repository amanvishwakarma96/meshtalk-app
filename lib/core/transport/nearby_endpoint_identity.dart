class NearbyEndpointIdentity {
  const NearbyEndpointIdentity({
    required this.deviceId,
    required this.displayName,
  });

  final String deviceId;
  final String displayName;
}

class NearbyEndpointIdentityCodec {
  const NearbyEndpointIdentityCodec();

  static const String _prefix = 'MT1';
  static final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9-]{8,64}$');

  String encode({
    required String deviceId,
    required String displayName,
  }) {
    if (!_deviceIdPattern.hasMatch(deviceId)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Nearby endpoint device IDs must contain 8-64 letters, numbers, or dashes.',
      );
    }

    return '$_prefix|$deviceId|${sanitizeDisplayName(displayName)}';
  }

  NearbyEndpointIdentity? decode(String endpointName) {
    final parts = endpointName.split('|');
    if (parts.length != 3 ||
        parts[0] != _prefix ||
        !_deviceIdPattern.hasMatch(parts[1])) {
      return null;
    }

    final displayName = sanitizeDisplayName(parts[2]);
    return NearbyEndpointIdentity(
      deviceId: parts[1],
      displayName: displayName,
    );
  }

  String sanitizeDisplayName(String displayName) {
    final normalized = displayName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final value = normalized.isEmpty ? 'MeshTalk' : normalized;
    return value.length <= 20 ? value : value.substring(0, 20);
  }
}
