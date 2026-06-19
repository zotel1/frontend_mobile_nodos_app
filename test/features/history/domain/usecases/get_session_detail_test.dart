import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/core/database/app_database.dart' hide ScanSession;
import 'package:frontend_mobile_nodos_app/features/history/domain/usecases/get_session_detail.dart';

/// T3.3: Tests para GetSessionDetail — consulta nodos de una sesión
/// con sus valores RSSI, uniendo scan_session_nodes con nodes.
///
/// S4.3: Sesión con 2 nodos → detalle muestra ambos con RSSI y nivel
/// de proximidad.
void main() {
  late AppDatabase db;
  late GetSessionDetail useCase;

  setUp(() async {
    db = AppDatabase.inMemory();
    useCase = GetSessionDetail(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ──

  Future<int> insertSession(DateTime startedAt) async {
    return db.into(db.scanSessions).insert(
          ScanSessionsCompanion.insert(
            startedAt: startedAt,
            nodesDetected: 0,
          ),
        );
  }

  Future<int> insertNode(String address, [String? name]) async {
    return db.into(db.nodes).insert(
          NodesCompanion(
            bleAddress: Value(address),
            name: Value(name),
            firstSeen: Value(DateTime(2026, 6, 1)),
            lastSeen: Value(DateTime(2026, 6, 19)),
            lastRssi: const Value(-60),
            proximityZone: const Value('medium'),
            rssiHistory: const Value('[-60]'),
          ),
        );
  }

  Future<void> insertSessionNode(int sessionId, int nodeId,
      [int rssi = -60]) async {
    await db.into(db.scanSessionNodes).insert(
          ScanSessionNodesCompanion.insert(
            sessionId: sessionId,
            nodeId: nodeId,
            rssi: rssi,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  group('T3.3: GetSessionDetail', () {
    test('retorna lista vacía cuando la sesión no tiene nodos', () async {
      final session = await insertSession(DateTime(2026, 6, 19));

      final result = await useCase(GetSessionDetailParams(sessionId: session));

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) => expect(nodes, isEmpty),
      );
    });

    test('retorna lista vacía cuando la sesión no existe', () async {
      final result =
          await useCase(GetSessionDetailParams(sessionId: 999));

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) => expect(nodes, isEmpty),
      );
    });

    test('retorna nodos con RSSI y nombre para una sesión con 2 nodos',
        () async {
      final session = await insertSession(DateTime(2026, 6, 19));
      final nodeA = await insertNode('AA:BB:CC:DD:EE:01', 'Nodo Alpha');
      final nodeB = await insertNode('AA:BB:CC:DD:EE:02', 'Nodo Beta');

      await insertSessionNode(session, nodeA, -45); // close range
      await insertSessionNode(session, nodeB, -75); // medium range

      final result = await useCase(GetSessionDetailParams(sessionId: session));

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) {
          expect(nodes.length, equals(2));

          // Verificar que ambos nodos están presentes con sus datos
          final nodeAData =
              nodes.firstWhere((n) => n.nodeId == nodeA);
          expect(nodeAData.rssi, equals(-45));
          expect(nodeAData.nodeName, equals('Nodo Alpha'));

          final nodeBData =
              nodes.firstWhere((n) => n.nodeId == nodeB);
          expect(nodeBData.rssi, equals(-75));
          expect(nodeBData.nodeName, equals('Nodo Beta'));
        },
      );
    });

    test('retorna nombre null para nodos sin nombre asignado', () async {
      final session = await insertSession(DateTime(2026, 6, 19));
      final node = await insertNode('FF:EE:DD:CC:BB:01', null); // sin nombre

      await insertSessionNode(session, node, -85);

      final result = await useCase(GetSessionDetailParams(sessionId: session));

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) {
          expect(nodes.length, equals(1));
          expect(nodes[0].nodeName, isNull);
          expect(nodes[0].rssi, equals(-85));
        },
      );
    });

    test('calcula proximityLevel correctamente desde RSSI', () async {
      final session = await insertSession(DateTime(2026, 6, 19));
      final closeNode = await insertNode('11:22:33:44:55:01');
      final mediumNode = await insertNode('11:22:33:44:55:02');
      final farNode = await insertNode('11:22:33:44:55:03');

      // RSSI > -70 → close
      await insertSessionNode(session, closeNode, -50);
      // -85 <= RSSI <= -70 → medium
      await insertSessionNode(session, mediumNode, -75);
      // RSSI < -85 → far
      await insertSessionNode(session, farNode, -90);

      final result = await useCase(GetSessionDetailParams(sessionId: session));

      result.fold(
        (_) => fail('Expected Right, got Left'),
        (nodes) {
          expect(nodes.length, equals(3));

          final close = nodes.firstWhere((n) => n.nodeId == closeNode);
          expect(close.proximityLevel, equals('close'));

          final medium = nodes.firstWhere((n) => n.nodeId == mediumNode);
          expect(medium.proximityLevel, equals('medium'));

          final far = nodes.firstWhere((n) => n.nodeId == farNode);
          expect(far.proximityLevel, equals('far'));
        },
      );
    });
  });
}
