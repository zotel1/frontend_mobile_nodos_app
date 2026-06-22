import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ──────────────────────── Users ────────────────────────

/// Tabla de perfil de usuario (singleton: exactamente un registro con id=1).
///
/// T-PR2-006: CHECK constraint fuerza que solo exista UN usuario.
/// La app es single-user — tener múltiples registros produce ambigüedad
/// porque getUser() usa getSingleOrNull() y retorna cualquiera.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get name => text()();
  TextColumn get color => text()();
  TextColumn get deviceType => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
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

  /// Indica si el dispositivo acepta conexiones GATT (Enlazar).
  ///
  /// T-PR2-006: Agregado en migración v3→v4. Nullable porque los nodos
  /// existentes antes de la migración no tienen este dato.
  /// false → el botón "Enlazar" se deshabilita en la UI.
  BoolColumn get connectable => boolean().nullable()();
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
///
/// T-PR2-005: Foreign keys con ON DELETE CASCADE. Al eliminar un nodo
/// o sesión, los registros correspondientes en esta tabla se eliminan
/// automáticamente, evitando edges fantasma en el grafo.
///
/// T-PR2-008: rssi ahora nullable — un valor null indica "sin datos de
/// RSSI" (antes se usaba el centinela mágico -100, indistinguible de
/// una señal RSSI real muy débil).
class ScanSessionNodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(
        ScanSessions, #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get nodeId => integer().references(
        Nodes, #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get rssi => integer().nullable()();

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
  ///
  /// T-PR2-005: Habilita foreign keys mediante el parámetro setup
  /// de NativeDatabase. SQLite no activa FK por defecto — sin esto,
  /// ON DELETE CASCADE y otras constraints no se aplican en tests.
  AppDatabase.inMemory()
      : super(NativeDatabase.memory(
          setup: (db) {
            db.execute('PRAGMA foreign_keys = ON;');
          },
        ));

  @override
  int get schemaVersion => 4;

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
          if (from < 3) {
            // Phase 4: identity enrichment columns (nullable, no data loss)
            await m.addColumn(nodes, nodes.suggestedName);
            await m.addColumn(nodes, nodes.deviceType);
          }
          if (from < 4) {
            // T-PR2-006: Migración v3→v4.
            //
            // Cambios:
            // 1. Agregar columna connectable (nullable bool) en Nodes.
            //    Los nodos existentes tendrán connectable = null → la UI
            //    asume connectable=true por defecto (compatible hacia atrás).
            //
            // 2. Recrear scan_session_nodes para aplicar ON DELETE CASCADE
            //    en las foreign keys y hacer rssi nullable.
            //    Drift no permite ALTER TABLE para cambiar constraints de FK,
            //    así que se recrea la tabla. Los datos existentes se pierden
            //    (scan_session_nodes es tabla transitoria de sesiones).
            //
            // 3. CHECH (id=1) en Users se aplica solo en nuevas BD.
            //    Las BD existentes con múltiples users no se reparan
            //    automáticamente (se requiere intervención manual).
            await m.addColumn(nodes, nodes.connectable);

            // Recrear scan_session_nodes con ON DELETE CASCADE y rssi nullable.
            await m.deleteTable('scan_session_nodes');
            await m.createTable(scanSessionNodes);
            await m.createIndex(scanSessionNodesSessionIdIdx);
          }
        },
      );
}
