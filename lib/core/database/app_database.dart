import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ──────────────────────── Nodes ────────────────────────

@DataClassName('NodeRow')
class Nodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Identidad estable del protocolo Nodos.
  ///
  /// Nullable para dispositivos BLE genéricos que no ejecutan Nodos.
  TextColumn get deviceUuid => text().nullable().unique()();

  /// Identificador BLE observado localmente (remoteId).
  ///
  /// Nullable porque el nodo propio existe aunque no se descubra
  /// a sí mismo mediante escaneo.
  TextColumn get bleAddress => text().nullable().unique()();

  /// Verdadero únicamente para el nodo que representa este dispositivo.
  BoolColumn get isSelf => boolean().withDefault(const Constant(false))();

  TextColumn get name => text().nullable()();
  TextColumn get color => text().nullable()();

  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();

  IntColumn get lastRssi => integer().nullable()();
  TextColumn get proximityZone => text().nullable()();
  TextColumn get rssiHistory => text().nullable()();

  TextColumn get suggestedName => text().nullable()();
  TextColumn get deviceType => text().nullable()();

  BoolColumn get connectable => boolean().withDefault(const Constant(false))();

  RealColumn get estimatedDistance => real().nullable()();
}

// ──────────────────────── Users ────────────────────────

/// Perfil único de la instalación.
///
/// IMPORTANTE:
/// `Users.id` identifica la fila de perfil.
/// NO representa un nodo del grafo.
///
/// [localNodeId] referencia al Node persistente que representa
/// este dispositivo.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get uuid => text().unique()();

  TextColumn get name => text()();

  TextColumn get color => text()();

  TextColumn get deviceType => text()();

  DateTimeColumn get createdAt => dateTime()();

  /// Referencia al nodo local persistente.
  ///
  /// Nullable para permitir:
  /// - migración desde bases anteriores;
  /// - creación inicial antes de EnsureLocalNode.
  ///
  /// ON DELETE SET NULL evita eliminar el perfil si accidentalmente
  /// desaparece el Node.
  IntColumn get localNodeId => integer().nullable().references(
    Nodes,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  List<String> get customConstraints => ['CHECK(id = 1)'];
}

// ──────────────────────── Connections ────────────────────────

class Connections extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get fromNodeId =>
      integer().references(Nodes, #id, onDelete: KeyAction.cascade)();

  IntColumn get toNodeId =>
      integer().references(Nodes, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => ['UNIQUE(from_node_id, to_node_id)'];
}

// ──────────────────────── ScanSessions ────────────────────────

class ScanSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get endedAt => dateTime().nullable()();

  IntColumn get nodesDetected => integer()();
}

// ──────────────────────── ScanSessionNodes ────────────────────────

class ScanSessionNodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get sessionId =>
      integer().references(ScanSessions, #id, onDelete: KeyAction.cascade)();

  IntColumn get nodeId =>
      integer().references(Nodes, #id, onDelete: KeyAction.cascade)();

  IntColumn get rssi => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE(session_id, node_id)'];
}

// ──────────────────────── Indexes ────────────────────────

final scanSessionNodesSessionIdIdx = Index(
  'scan_session_nodes_session_id_idx',
  'CREATE INDEX scan_session_nodes_session_id_idx '
      'ON scan_session_nodes(session_id)',
);

final nodesBleAddressIdx = Index(
  'idx_nodes_ble_address',
  'CREATE INDEX idx_nodes_ble_address ON nodes(ble_address)',
);

final nodesDeviceUuidIdx = Index(
  'idx_nodes_device_uuid',
  'CREATE INDEX idx_nodes_device_uuid ON nodes(device_uuid)',
);

final nodesIsSelfIdx = Index(
  'idx_nodes_is_self',
  'CREATE UNIQUE INDEX idx_nodes_is_self '
      'ON nodes(is_self) WHERE is_self = 1',
);

final scanSessionNodesNodeIdIdx = Index(
  'idx_scan_session_nodes_node_id',
  'CREATE INDEX idx_scan_session_nodes_node_id '
      'ON scan_session_nodes(node_id)',
);

final scanSessionsStartedAtIdx = Index(
  'idx_scan_sessions_started_at',
  'CREATE INDEX idx_scan_sessions_started_at '
      'ON scan_sessions(started_at)',
);

final connectionsFromNodeIdIdx = Index(
  'idx_connections_from_node_id',
  'CREATE INDEX idx_connections_from_node_id '
      'ON connections(from_node_id)',
);

final connectionsToNodeIdIdx = Index(
  'idx_connections_to_node_id',
  'CREATE INDEX idx_connections_to_node_id '
      'ON connections(to_node_id)',
);

// ──────────────────────── Database ────────────────────────

@DriftDatabase(
  tables: [Nodes, Users, Connections, ScanSessions, ScanSessionNodes],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({required String encryptionKey})
    : super(
        driftDatabase(
          name: 'nodos',
          native: DriftNativeOptions(
            setup: (db) {
              db.execute("PRAGMA key='$encryptionKey'");
            },
          ),
        ),
      );

  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();

      await m.createIndex(scanSessionNodesSessionIdIdx);
      await m.createIndex(connectionsFromNodeIdIdx);
      await m.createIndex(connectionsToNodeIdIdx);
      await m.createIndex(nodesBleAddressIdx);
      await m.createIndex(nodesDeviceUuidIdx);
      await m.createIndex(nodesIsSelfIdx);
      await m.createIndex(scanSessionNodesNodeIdIdx);
      await m.createIndex(scanSessionsStartedAtIdx);
    },

    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(scanSessionNodes);
        await m.createIndex(scanSessionNodesSessionIdIdx);
      }

      if (from < 3) {
        await m.addColumn(nodes, nodes.suggestedName);
        await m.addColumn(nodes, nodes.deviceType);
      }

      if (from < 4) {
        await m.createTable(connections);
        await m.addColumn(nodes, nodes.connectable);
        await m.addColumn(nodes, nodes.estimatedDistance);
      }

      if (from < 5) {
        await m.createIndex(connectionsFromNodeIdIdx);
        await m.createIndex(connectionsToNodeIdIdx);

        await m.deleteTable(scanSessionNodes.actualTableName);
        await m.createTable(scanSessionNodes);
        await m.createIndex(scanSessionNodesSessionIdIdx);
      }

      if (from < 6) {
        await m.createIndex(nodesBleAddressIdx);
        await m.createIndex(scanSessionNodesNodeIdIdx);
        await m.createIndex(scanSessionsStartedAtIdx);

        await m.deleteTable(scanSessionNodes.actualTableName);
        await m.createTable(scanSessionNodes);

        await m.createIndex(scanSessionNodesSessionIdIdx);
        await m.createIndex(scanSessionNodesNodeIdIdx);

        await m.deleteTable(users.actualTableName);
        await m.createTable(users);
      }

      if (from < 7) {
        // ARCH-001:
        //
        // La migración estructural completa v6 → v7 se termina
        // en el siguiente bloque de implementación.
        //
        // No reutilizamos Nodes.id=1 como self-node.
        //
        // Aquí todavía NO insertamos el self-node porque su creación
        // debe pasar por EnsureLocalNode usando el UUID persistente.
        //
        // TableMigration permite a Drift recrear `nodes` con el
        // schema nuevo preservando columnas compatibles y haciendo
        // ble_address nullable.
        await m.alterTable(
          TableMigration(nodes, newColumns: [nodes.deviceUuid, nodes.isSelf]),
        );

        await m.addColumn(users, users.localNodeId);

        await m.createIndex(nodesDeviceUuidIdx);
        await m.createIndex(nodesIsSelfIdx);
      }
    },

    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
