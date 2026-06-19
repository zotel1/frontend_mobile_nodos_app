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
  IntColumn get sessionId => integer().references(ScanSessions, #id)();
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

@DriftDatabase(tables: [Users, Nodes, ScanSessions, ScanSessionNodes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'nodos'));

  /// Constructor en memoria para testing.
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // Índice para queries por sesión en scan_session_nodes.
          await m.createIndex(scanSessionNodesSessionIdIdx);
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(scanSessionNodes);
            // Índice para queries por sesión en scan_session_nodes.
            await m.createIndex(scanSessionNodesSessionIdIdx);
          }
        },
      );
}
