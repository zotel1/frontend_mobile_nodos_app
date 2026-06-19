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

// ──────────────────────── Database ────────────────────────

@DriftDatabase(tables: [Users, Nodes, ScanSessions])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'nodos'));

  /// In-memory constructor for testing.
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );
}
