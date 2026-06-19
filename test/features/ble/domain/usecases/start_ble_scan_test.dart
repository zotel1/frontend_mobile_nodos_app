import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/usecases/start_ble_scan.dart';

@GenerateNiceMocks([MockSpec<BleRepository>()])
import 'start_ble_scan_test.mocks.dart';

void main() {
  late MockBleRepository mockRepository;
  late StartBleScan useCase;

  setUp(() {
    mockRepository = MockBleRepository();
    useCase = StartBleScan(mockRepository);
  });

  group('StartBleScan', () {
    test('calls repository.startScan()', () async {
      // arrange
      when(mockRepository.startScan()).thenAnswer((_) async {});

      // act
      final result = await useCase(const NoParams());

      // assert
      verify(mockRepository.startScan()).called(1);
      expect(result.isRight(), isTrue);
    });

    test('returns Left(Failure) when repository throws', () async {
      // arrange
      when(mockRepository.startScan()).thenThrow(Exception('BT error'));

      // act
      final result = await useCase(const NoParams());

      // assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, contains('BT error')),
        (_) => fail('Expected Left, got Right'),
      );
    });
  });
}
