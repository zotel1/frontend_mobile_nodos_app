import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ──────────────────────── Users ────────────────────────

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get name => text()();
  TextColumn get color => text()();
  TextColumn get deviceType => text()();
  DateTimeColumn get createdAt => dateTime()();
}

// ──────────────────────── Nodes ────────────────────────

  @DataClassName('NodeRow')
class Nodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bleAddress => text().unique()();
  TextColumn get name => text().nullable()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();
  IntColumn get lastRssi => integer().nullable()();
  TextColumn get proximityZone => text().nullable()();
  TextColumn get rssiHistory => text().nullable()(); // JSON array
  // Phase 4 identity enrichment
  TextColumn get suggestedName => text().nullable()();
  TextColumn get deviceType => text().nullable()();
  // Phase 5 graph social model
  BoolColumn get connectable => boolean().withDefault(const Constant(false))();
  RealColumn get estimatedDistance => real().nullable()();
}

// ──────────────────────── Connections ────────────────────────
//
// QUÉ: tabla que registra conexiones BLE exitosas entre nodos.
// Las aristas del grafo social se derivan de esta tabla
// (no de co-detección). UNIQUE(from, to) evita duplicados.
// ON DELETE CASCADE: si un nodo se elimina, sus conexiones
// asociadas se borran automáticamente.

class Connections extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fromNodeId => integer().references(Nodes, #id,
      onDelete: KeyAction.cascade)();
  IntColumn get toNodeId => integer().references(Nodes, #id,
      onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => [
        'UNIQUE(from_node_id, to_node_id)',
      ];
}

// ──────────────────────── ScanSessions ────────────────────────

class ScanSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get nodesDetected => integer()();
}

// ──────────────────────── ScanSessionNodes ────────────────────────

/// Tabla de unión entre sesiones de escaneo y nodos detectados.
/// Registra qué nodos fueron detectados en cada sesión junto con su RSSI.
/// La combinación (sessionId, nodeId) es única para evitar duplicados.
/// Tabla de unión entre sesiones de escaneo y nodos detectados.
/// Registra qué nodos fueron detectados en cada sesión junto con su RSSI.
/// La combinación (sessionId, nodeId) es única para evitar duplicados.
class ScanSessionNodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(ScanSessions, #id,
      onDelete: KeyAction.cascade)();
  IntColumn get nodeId => integer().references(Nodes, #id)();
  IntColumn get rssi => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE(session_id, node_id)'];
}

/// Índice sobre sessionId en scan_session_nodes para acelerar queries de edges.
final scanSessionNodesSessionIdIdx = Index(
  'scan_session_nodes_session_id_idx',
  'CREATE INDEX scan_session_nodes_session_id_idx '
  'ON scan_session_nodes(session_id)',
);

// ──────────────────────── Database ────────────────────────

@DriftDatabase(tables: [Users, Nodes, Connections, ScanSessions, ScanSessionNodes])
class AppDatabase extends _$AppDatabase {
  /// Constructor de producción con cifrado SQLCipher.
  ///
  /// QUÉ: abre la base de datos con una clave de cifrado derivada del dispositivo.
  /// Sin la clave correcta, el archivo SQLite es ilegible.
  ///
  /// POR QUÉ: R14 — la base de datos debe estar cifrada en reposo para proteger
  /// la privacidad de los datos de proximidad del usuario.
  AppDatabase({required String encryptionKey})
      : super(driftDatabase(
          name: 'nodos',
          native: DriftNativeOptions(
            setup: (db) {
              db.execute("PRAGMA key='$encryptionKey'");
            },
          ),
        ));

  /// Constructor en memoria para testing (sin cifrado).
  ///
  /// QUÉ: crea una base de datos en memoria sin cifrar para pruebas unitarias.
  /// Los tests no necesitan cifrado y requieren ejecución rápida.
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // Índice para queries por sesión en scan_session_nodes.
          await m.createIndex(scanSessionNodesSessionIdIdx);
          // Índices en connections para acelerar queries de grafo social (R15).
          await m.createIndex(connectionsFromNodeIdIdx);
          await m.createIndex(connectionsToNodeIdIdx);
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(scanSessionNodes);
            // Índice para queries por sesión en scan_session_nodes.
            await m.createIndex(scanSessionNodesSessionIdIdx);
          }
          if (from < 3) {
            // Phase 4: identity enrichment columns (nullable, no data loss)
            await m.addColumn(nodes, nodes.suggestedName);
            await m.addColumn(nodes, nodes.deviceType);
          }
          if (from < 4) {
            // Phase 5: tabla connections para grafo social + nuevos campos en nodes
            await m.createTable(connections);
            await m.addColumn(nodes, nodes.connectable);
            await m.addColumn(nodes, nodes.estimatedDistance);
          }
          if (from < 5) {
            // PR4: índices en connections + CASCADE en scan_session_nodes
            // R15: índices no únicos para acelerar búsquedas de aristas.
            await m.createIndex(connectionsFromNodeIdIdx);
            await m.createIndex(connectionsToNodeIdIdx);

            // R16: recrear scan_session_nodes con ON DELETE CASCADE.
            // SQLite no soporta ALTER TABLE para modificar FKs → recrear tabla.
            await m.deleteTable(scanSessionNodes.actualTableName);
            await m.createTable(scanSessionNodes);
            await m.createIndex(scanSessionNodesSessionIdIdx);
          }
        },
        beforeOpen: (details) async {
          // Habilitar enforcement de foreign keys (requerido para CASCADE).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// Índice sobre fromNodeId en connections para acelerar queries
/// de aristas salientes (R15).
final connectionsFromNodeIdIdx = Index(
  'idx_connections_from_node_id',
  'CREATE INDEX idx_connections_from_node_id ON connections(from_node_id)',
);

/// Índice sobre toNodeId en connections para acelerar queries
/// de aristas entrantes (R15).
final connectionsToNodeIdIdx = Index(
  'idx_connections_to_node_id',
  'CREATE INDEX idx_connections_to_node_id ON connections(to_node_id)',
);
