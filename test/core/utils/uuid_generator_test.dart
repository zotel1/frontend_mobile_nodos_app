import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/utils/uuid_generator.dart';

void main() {
  group('generateUuidV4', () {
    test('returns a 36-character string', () {
      final uuid = generateUuidV4();
      expect(uuid.length, 36);
    });

    test('matches RFC 4122 UUID v4 format (xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx)', () {
      final uuid = generateUuidV4();
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(uuidPattern.hasMatch(uuid), isTrue,
          reason: '$uuid does not match UUID v4 format');
    });

    test('generates unique values across 100 generations', () {
      final uuids = <String>{};
      for (var i = 0; i < 100; i++) {
        uuids.add(generateUuidV4());
      }
      expect(uuids.length, 100,
          reason: 'Expected 100 unique UUIDs, got ${uuids.length}');
    });
  });
}
