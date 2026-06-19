import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/history/domain/entities/session_node.dart';

/// Parámetros para GetSessionDetail: el ID de la sesión.
class GetSessionDetailParams extends Equatable {
  final int sessionId;

  const GetSessionDetailParams({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

/// Consulta los nodos detectados en una sesión específica con sus
/// valores RSSI y nivel de proximidad.
///
/// QUÉ: hace JOIN entre scan_session_nodes y nodes para obtener
/// el nombre del nodo (si existe) y el RSSI medido en esa sesión.
/// Deriva el nivel de proximidad desde el RSSI usando rssiToProximity.
///
/// POR QUÉ: el detalle de una sesión debe mostrar qué nodos fueron
/// detectados y con qué intensidad de señal. La proximidad ayuda
/// al usuario a entender qué tan cerca estaban los dispositivos.
///
/// Retorna `Either<Failure, List<SessionNode>>`.
class GetSessionDetail {
  final AppDatabase _db;

  const GetSessionDetail(this._db);

  Future<Either<Failure, List<SessionNode>>> call(
      GetSessionDetailParams params) async {
    try {
      final query = _db.customSelect(
        'SELECT sn.id, sn.session_id, sn.node_id, sn.rssi, '
        'n.name AS node_name '
        'FROM scan_session_nodes sn '
        'JOIN nodes n ON sn.node_id = n.id '
        'WHERE sn.session_id = ?',
        variables: [Variable.withInt(params.sessionId)],
      );

      final rows = await query.get();

      final nodes = rows.map((row) {
        final rssi = row.read<int>('rssi');
        final proximity = rssiToProximity(rssi);

        // Mapear el nivel de proximidad a string legible
        String proximityLevel;
        switch (proximity) {
          case ProximityLevel.close:
            proximityLevel = 'close';
          case ProximityLevel.medium:
            proximityLevel = 'medium';
          case ProximityLevel.far:
            proximityLevel = 'far';
        }

        return SessionNode(
          id: row.read<int>('id'),
          sessionId: row.read<int>('session_id'),
          nodeId: row.read<int>('node_id'),
          rssi: rssi,
          nodeName: row.read<String?>('node_name'),
          proximityLevel: proximityLevel,
        );
      }).toList();

      return Right(nodes);
    } catch (e) {
      return Left(UnexpectedFailure('Error al cargar detalle: $e'));
    }
  }
}
