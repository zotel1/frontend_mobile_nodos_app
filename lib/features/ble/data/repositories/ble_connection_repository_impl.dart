import 'package:drift/drift.dart' hide Column;
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_connection_repository.dart';

/// Implementación concreta de [BleConnectionRepository].
///
/// QUÉ: delega las operaciones GATT a [BleGattDataSource] y la
/// persistencia de conexiones a [AppDatabase] (tabla connections).
///
/// POR QUÉ: centraliza la infraestructura de conexión en un solo punto.
/// El [BleConnectionBloc] depende de esta abstracción en lugar de
/// depender directamente de datasources concretos y de la base de datos.
class BleConnectionRepositoryImpl implements BleConnectionRepository {
  final BleGattDataSource _gatt;
  final AppDatabase _db;

  BleConnectionRepositoryImpl({
    required BleGattDataSource gatt,
    required AppDatabase db,
  })  : _gatt = gatt,
        _db = db;

  @override
  Future<void> connect(String remoteId) async {
    await _gatt.connect(remoteId);
  }

  @override
  Future<void> disconnect(String remoteId) async {
    await _gatt.disconnect(remoteId);
  }

  @override
  Stream<bool> connectionState(String remoteId) {
    return _gatt.connectionState(remoteId);
  }

  @override
  Future<void> discoverServices(String remoteId) async {
    await _gatt.discoverServices(remoteId);
  }

  @override
  Future<List<int>?> readCharacteristic(
      String remoteId, String characteristicUuid) async {
    return _gatt.readCharacteristic(remoteId, characteristicUuid);
  }

  @override
  Future<void> saveConnection(int fromNodeId, int toNodeId) async {
    await _db.into(_db.connections).insert(
          ConnectionsCompanion.insert(
            fromNodeId: fromNodeId,
            toNodeId: toNodeId,
            createdAt: DateTime.now(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
