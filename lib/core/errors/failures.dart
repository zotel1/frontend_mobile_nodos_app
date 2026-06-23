import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}

class BluetoothFailure extends Failure {
  const BluetoothFailure([super.message = 'Bluetooth error']);
}

/// Fallo de base de datos (corrupción, constraint, esquema).
///
/// QUÉ: representa errores de capa de persistencia que NO son
/// recuperables automáticamente. Distinto de [CacheFailure] que
/// indica ausencia de datos (no error estructural).
///
/// POR QUÉ: el UserBloc necesita diferenciar "no hay perfil" (CacheFailure)
/// de "la DB está rota" (DatabaseFailure) para decidir si crear o no
/// un perfil default automáticamente.
class DatabaseFailure extends Failure {
  const DatabaseFailure([super.message = 'Database error']);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Unexpected error']);
}
