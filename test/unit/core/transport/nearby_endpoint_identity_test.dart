import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/transport/nearby_endpoint_identity.dart';

void main() {
  const codec = NearbyEndpointIdentityCodec();

  test('round-trips a stable endpoint identity', () {
    final encoded = codec.encode(
      deviceId: '550e8400-e29b-41d4-a716-446655440000',
      displayName: 'Trail Phone',
    );

    final identity = codec.decode(encoded);

    expect(identity, isNotNull);
    expect(identity!.deviceId, '550e8400-e29b-41d4-a716-446655440000');
    expect(identity.displayName, 'Trail Phone');
  });

  test('sanitizes and bounds advertised display names', () {
    final encoded = codec.encode(
      deviceId: '550e8400-e29b-41d4-a716-446655440000',
      displayName: '  Mesh 🔥   Phone With A Very Long Name  ',
    );

    final identity = codec.decode(encoded)!;

    expect(identity.displayName, 'Mesh Phone With A Ver');
    expect(identity.displayName.length, 20);
  });

  test('rejects malformed endpoint identities', () {
    expect(codec.decode('not-meshtalk'), isNull);
    expect(codec.decode('MT1|short|Peer'), isNull);
    expect(codec.decode('MT2|550e8400-e29b-41d4-a716-446655440000|Peer'), isNull);
  });

  test('rejects invalid local device identifiers', () {
    expect(
      () => codec.encode(deviceId: 'bad id', displayName: 'Peer'),
      throwsArgumentError,
    );
  });
}
