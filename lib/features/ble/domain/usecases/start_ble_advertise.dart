import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';

class StartBleAdvertiseParams extends Equatable {
  final String deviceUuid;

  const StartBleAdvertiseParams({required this.deviceUuid});

  @override
  List<Object> get props => [deviceUuid];
}

class StartBleAdvertise extends UseCase<void, StartBleAdvertiseParams> {
  final BleRepository repository;

  StartBleAdvertise(this.repository);

  @override
  Future<Either<Failure, void>> call(StartBleAdvertiseParams params) async {
    try {
      await repository.startAdvertise(params.deviceUuid);
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
