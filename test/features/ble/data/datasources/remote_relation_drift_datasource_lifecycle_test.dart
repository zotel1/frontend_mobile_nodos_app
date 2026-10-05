import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';

import 'package:frontend_mobile_nodos_app/core/database/app_database.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/remote_relation_drift_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';

void main() {
  late AppDatabase database;
  late RemoteRelationDriftDataSource datasource;

  setUp(() {
    database = AppDatabase.inMemory();
    datasource = RemoteRelationDriftDataSource(database);
  });

  tearDown(() async => database.close());

  test('clears stale snapshots without touching the nodes catalog', () async {
    await datasource.replaceSnapshot(
      reporterUuid: 'reporter-a',
      connections: [NodosGraphConnection.nodos(deviceUuid: 'peer-b')],
    );

    await database
        .into(database.nodes)
        .insert(
          NodesCompanion.insert(
            deviceUuid: const Value('known-node'),
            firstSeen: DateTime(2026, 1, 1),
            lastSeen: DateTime(2026, 1, 1),
          ),
        );

    await datasource.clearAllSnapshots();

    expect(await datasource.getSnapshot('reporter-a'), isEmpty);
    expect(await (database.select(database.nodes)).get(), hasLength(1));
  });

  test('clearing snapshots is idempotent', () async {
    await datasource.clearAllSnapshots();
    await datasource.clearAllSnapshots();

    expect(await (database.select(database.remoteRelations)).get(), isEmpty);
  });
}
