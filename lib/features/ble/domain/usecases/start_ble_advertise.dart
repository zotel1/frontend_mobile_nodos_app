import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';

/// Parámetros para iniciar el advertising BLE con los metadatos de
/// identidad del dispositivo (uuid, name, color).
class StartBleAdvertiseParams extends Equatable {
  final String deviceUuid;
  final String name;
  final String color;

  const StartBleAdvertiseParams({
    required this.deviceUuid,
    required this.name,
    required this.color,
  });

  @override
  List<Object> get props => [deviceUuid, name, color];
}

/// Caso de uso que inicia el advertising BLE en modo periférico.
///
/// QUÉ hace: delega en [BleRepository.startAdvertise] con los metadatos
/// de identidad (uuid, name, color) para que otros dispositivos Nodos
/// detecten este dispositivo vía escaneo BLE.
class StartBleAdvertise extends UseCase<void, StartBleAdvertiseParams> {
  final BleRepository repository;

  StartBleAdvertise(this.repository);

  @override
  Future<Either<Failure, void>> call(StartBleAdvertiseParams params) async {
    try {
      await repository.startAdvertise(
        params.deviceUuid,
        params.name,
        params.color,
      );
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
