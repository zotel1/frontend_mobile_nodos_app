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

  /// Referencia namespaced recibida mediante Graph Exchange.
  ///
  /// Se utiliza para materializar localmente dispositivos BLE genéricos
  /// conocidos únicamente a través de otra instalación Nodos.
  ///
  /// Ejemplo:
  ///
  ///   local:`reporterUuid:42`
  ///
  /// Esta referencia NO es:
  /// - una dirección BLE;
  /// - un UUID global;
  /// - evidencia de que el dispositivo fue detectado localmente.
  ///
  /// Es null para:
  /// - el self-node;
  /// - dispositivos detectados localmente;
  /// - instalaciones Nodos identificables mediante [deviceUuid].
  ///
  /// Para un dispositivo BLE genérico remoto, [remoteRef] constituye
  /// su identidad estable dentro del namespace del reporter.
  TextColumn get remoteRef => text().nullable().unique()();

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

/// Relaciones directas creadas por esta instalación.
///
/// Esta tabla NO contiene relaciones aprendidas desde otros dispositivos
/// mediante Graph Exchange.
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

// ──────────────────────── RemoteRelations ────────────────────────

/// Relación directa declarada por otra instalación Nodos.
///
/// Ejemplo:
///
/// El Motorola recibe del A25:
///
///   A25 ── JBL Charge 3
///
/// Motorola NO inserta esa relación en [Connections], porque no es una
/// relación creada localmente. En cambio almacena aquí que el A25 declaró
/// una relación con un nodo remoto.
///
/// [reporterUuid] identifica a la instalación Nodos que publicó la relación.
///
/// [remoteRef] identifica al otro extremo dentro del protocolo distribuido:
///
/// - `nodos:<deviceUuid>` para otra instalación Nodos.
/// - `local:<reporterUuid>:<localNodeId>` para un BLE genérico conocido
///   únicamente por el dispositivo que publica el grafo.
///
/// El segundo formato NO constituye una identidad global del dispositivo BLE.
/// Es solamente una referencia estable dentro del namespace del reporter.
class RemoteRelations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// UUID estable de la instalación Nodos que declara la relación.
  TextColumn get reporterUuid => text()();

  /// Referencia transportable del otro extremo de la relación.
  TextColumn get remoteRef => text()();

  /// UUID Nodos del nodo remoto, cuando existe.
  ///
  /// Es null para dispositivos BLE genéricos.
  TextColumn get remoteDeviceUuid => text().nullable()();

  /// Nombre que el reporter conoce para el nodo remoto.
  TextColumn get remoteName => text().nullable()();

  /// Color Nodos cuando el extremo remoto es otra instalación Nodos.
  TextColumn get remoteColor => text().nullable()();

  /// Tipo de dispositivo conocido por el reporter.
  TextColumn get remoteDeviceType => text().nullable()();

  /// Momento en que esta instalación recibió por última vez
  /// esta relación desde el reporter.
  DateTimeColumn get lastReceivedAt => dateTime()();

  @override
  List<String> get customConstraints => ['UNIQUE(reporter_uuid, remote_ref)'];
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

final nodesRemoteRefIdx = Index(
  'idx_nodes_remote_ref',
  'CREATE INDEX idx_nodes_remote_ref ON nodes(remote_ref)',
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

final remoteRelationsReporterUuidIdx = Index(
  'idx_remote_relations_reporter_uuid',
  'CREATE INDEX idx_remote_relations_reporter_uuid '
      'ON remote_relations(reporter_uuid)',
);

final remoteRelationsRemoteDeviceUuidIdx = Index(
  'idx_remote_relations_remote_device_uuid',
  'CREATE INDEX idx_remote_relations_remote_device_uuid '
      'ON remote_relations(remote_device_uuid)',
);

// ──────────────────────── Database ────────────────────────

@DriftDatabase(
  tables: [
    Nodes,
    Users,
    Connections,
    RemoteRelations,
    ScanSessions,
    ScanSessionNodes,
  ],
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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();

      await m.createIndex(scanSessionNodesSessionIdIdx);
      await m.createIndex(connectionsFromNodeIdIdx);
      await m.createIndex(connectionsToNodeIdIdx);
      await m.createIndex(nodesBleAddressIdx);
      await m.createIndex(nodesDeviceUuidIdx);
      await m.createIndex(nodesRemoteRefIdx);
      await m.createIndex(nodesIsSelfIdx);
      await m.createIndex(scanSessionNodesNodeIdIdx);
      await m.createIndex(scanSessionsStartedAtIdx);
      await m.createIndex(remoteRelationsReporterUuidIdx);
      await m.createIndex(remoteRelationsRemoteDeviceUuidIdx);
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

      if (from < 8) {
        // FEAT-002:
        //
        // Las relaciones recibidas desde otras instalaciones Nodos
        // se mantienen separadas de las conexiones directas locales.
        //
        // Esto preserva la semántica de `connections` y permite saber
        // qué instalación declaró cada relación.
        await m.createTable(remoteRelations);
        await m.createIndex(remoteRelationsReporterUuidIdx);
        await m.createIndex(remoteRelationsRemoteDeviceUuidIdx);
      }

      if (from < 9) {
        // FEAT-002:
        //
        // Los dispositivos BLE genéricos aprendidos mediante Graph Exchange
        // necesitan un Node.id local para participar del sistema de
        // visualización existente.
        //
        // remote_ref conserva la identidad namespaced declarada por el
        // reporter sin reutilizar ble_address ni inventar un device_uuid.
        //
        // Ejemplo:
        // local:`local:reporterUuid:42`
        await m.addColumn(nodes, nodes.remoteRef);
        await m.createIndex(nodesRemoteRefIdx);
      }
    },

    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
