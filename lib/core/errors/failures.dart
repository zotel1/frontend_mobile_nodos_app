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

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Unexpected error']);
}
