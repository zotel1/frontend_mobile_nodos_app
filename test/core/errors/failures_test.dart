import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';

void main() {
  group('Failure', () {
    test('CacheFailure has correct default message', () {
      const failure = CacheFailure();
      expect(failure.message, 'Cache error');
    });

    test('BluetoothFailure has correct default message', () {
      const failure = BluetoothFailure();
      expect(failure.message, 'Bluetooth error');
    });

    test('UnexpectedFailure has correct default message', () {
      const failure = UnexpectedFailure();
      expect(failure.message, 'Unexpected error');
    });

    test('CacheFailure accepts custom message', () {
      const failure = CacheFailure('Custom cache error');
      expect(failure.message, 'Custom cache error');
    });

    test('BluetoothFailure accepts custom message', () {
      const failure = BluetoothFailure('Custom BT error');
      expect(failure.message, 'Custom BT error');
    });

    test('UnexpectedFailure accepts custom message', () {
      const failure = UnexpectedFailure('Custom unexpected error');
      expect(failure.message, 'Custom unexpected error');
    });

    group('equality via Equatable', () {
      test('two CacheFaliures with same message are equal', () {
        const a = CacheFailure('msg');
        const b = CacheFailure('msg');
        expect(a, equals(b));
      });

      test('two CacheFailures with different messages are not equal', () {
        const a = CacheFailure('msg1');
        const b = CacheFailure('msg2');
        expect(a, isNot(equals(b)));
      });

      test('different Failure subtypes are not equal', () {
        const a = CacheFailure('msg');
        const b = BluetoothFailure('msg');
        expect(a, isNot(equals(b)));
      });

      test('two BluetoothFailures with same message are equal', () {
        const a = BluetoothFailure('msg');
        const b = BluetoothFailure('msg');
        expect(a, equals(b));
      });

      test('two UnexpectedFailures with same message are equal', () {
        const a = UnexpectedFailure('msg');
        const b = UnexpectedFailure('msg');
        expect(a, equals(b));
      });
    });
  });
}
