import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';

@GenerateNiceMocks([
  MockSpec<ObserveNodes>(),
  MockSpec<UpdateNodeMetadata>(),
  MockSpec<NodeRepository>(),
])
import 'node_list_bloc_test.mocks.dart';

void main() {
  late MockObserveNodes mockObserveNodes;
  late MockUpdateNodeMetadata mockUpdateNodeMetadata;
  late MockNodeRepository mockNodeRepository;

  final now = DateTime(2026, 1, 1);

  final testNodes = [
    Node(
      id: 1,
      bleAddress: 'AA:BB:CC:DD:EE:FF',
      name: 'Node 1',
      color: '#2196F3',
      firstSeen: now,
      lastSeen: now,
      rssiHistory: const [-45],
    ),
    Node(
      id: 2,
      bleAddress: '11:22:33:44:55:66',
      name: null,
      color: null,
      firstSeen: now,
      lastSeen: now,
      rssiHistory: const [-80],
    ),
  ];

  setUp(() {
    mockObserveNodes = MockObserveNodes();
    mockUpdateNodeMetadata = MockUpdateNodeMetadata();
    mockNodeRepository = MockNodeRepository();
  });

  group('NodeListBloc', () {
    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListInitial] as initial state',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      verify: (bloc) => expect(bloc.state, isA<NodeListInitial>()),
    );

    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListLoading, NodeListLoaded] when LoadNodes is added '
      'and stream emits nodes',
      build: () {
        when(mockObserveNodes.call())
            .thenAnswer((_) => Stream.value(testNodes));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(LoadNodes()),
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListLoaded>().having(
          (s) => s.nodes,
          'nodes',
          equals(testNodes),
        ),
      ],
    );

    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListLoading, NodeListEmpty] when LoadNodes is added '
      'and stream emits empty list',
      build: () {
        when(mockObserveNodes.call())
            .thenAnswer((_) => Stream.value([]));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(LoadNodes()),
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListEmpty>(),
      ],
    );

    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListError] when observeNodes stream throws',
      build: () {
        when(mockObserveNodes.call()).thenAnswer(
            (_) => Stream.error(Exception('DB error')));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(LoadNodes()),
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListError>().having(
          (s) => s.message,
          'message',
          contains('DB error'),
        ),
      ],
    );

    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListLoaded] when NodeDetected is added',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(NodeDetected(testNodes[0])),
      expect: () => [
        isA<NodeListLoaded>().having(
          (s) => s.nodes,
          'nodes',
          equals([testNodes[0]]),
        ),
      ],
    );

    blocTest<NodeListBloc, NodeListState>(
      'handles RefreshNodes by re-emitting current state if loaded',
      seed: () => NodeListLoaded(testNodes),
      build: () {
        when(mockObserveNodes.call())
            .thenAnswer((_) => Stream.value(testNodes));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(RefreshNodes()),
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListLoaded>().having(
          (s) => s.nodes,
          'nodes',
          equals(testNodes),
        ),
      ],
    );

    blocTest<NodeListBloc, NodeListState>(
      'handles RefreshNodes from empty state',
      seed: () => const NodeListEmpty(),
      build: () {
        when(mockObserveNodes.call())
            .thenAnswer((_) => Stream.value([]));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(RefreshNodes()),
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListEmpty>(),
      ],
    );

    // T1.6 F6: SyncBleDevices debe suscribirse al stream Drift
    // si no hay suscripción activa, emitiendo NodeListLoaded
    // con los nodos persistidos.
    // QUÉ: cuando SyncBleDevices persiste nodos y no hay
    // _nodesSubscription activo, el BLoC debe llamar a
    // _subscribeToNodes para iniciar el watcher Drift.
    // POR QUÉ: sin esta suscripción, los nodos persistidos
    // nunca se reflejan en la UI.
    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListLoaded] after SyncBleDevices when Drift stream emits nodes',
      build: () {
        // Configurar el mock de NodeRepository para upsertNode.
        when(mockNodeRepository.upsertNode(any))
            .thenAnswer((_) async {});
        // Configurar ObserveNodes para emitir la lista de nodos.
        when(mockObserveNodes.call())
            .thenAnswer((_) => Stream.value(testNodes));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(SyncBleDevices([
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          rssi: -45,
          distance: 1.0,
          proximity: ProximityLevel.close,
          timestamp: now,
        ),
      ])),
      // La suscripción al stream se activa al final de _onSyncBleDevices,
      // emitiendo NodeListLoaded con los nodos del stream Drift.
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListLoaded>().having(
          (s) => s.nodes.length,
          'nodes.length',
          2, // testNodes tiene 2 nodos
        ),
      ],
    );

    // ── T-PR1-009 RED: SyncBleDevices no debe emitir NodeListLoading ─
    // QUÉ: cuando el estado actual ya es NodeListLoaded (nodos ya visibles),
    // SyncBleDevices NO debe emitir NodeListLoading porque causaría un
    // flicker: la UI mostraría un spinner por un instante, luego la lista
    // de nodos otra vez.
    // POR QUÉ: actualmente _onSyncBleDevices llama a _subscribeToNodes
    // que siempre emite NodeListLoading. Durante escaneo BLE continuo,
    // esto causa parpadeo (flicker) cada vez que llegan nuevos dispositivos.
    // El fix: si ya hay _nodesSubscription activa (state is NodeListLoaded),
    // no re-suscribirse ni emitir loading.
    blocTest<NodeListBloc, NodeListState>(
      'T-PR1-009 RED: SyncBleDevices cuando ya está NodeListLoaded NO emite NodeListLoading',
      seed: () => NodeListLoaded(testNodes),
      build: () {
        // Configurar ObserveNodes para que emita (simulando suscripción activa).
        when(mockObserveNodes.call())
            .thenAnswer((_) => Stream.value(testNodes));
        when(mockNodeRepository.upsertNode(any))
            .thenAnswer((_) async {});
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(SyncBleDevices([
        BleDevice(
          deviceId: 'BB:CC:DD:EE:FF:00',
          rssi: -60,
          distance: 2.0,
          proximity: ProximityLevel.medium,
          timestamp: now,
        ),
      ])),
      // En RED: el test espera que NO se emita NodeListLoading.
      // Actualmente _subscribeToNodes SIEMPRE emite NodeListLoading.
      // El test fallará porque ve NodeListLoading en la secuencia.
      expect: () => [
        // No debe haber NodeListLoading
        // La suscripción existente emitirá los nodos actualizados
      ],
      // Verificar que upsertNode fue llamado para el nuevo dispositivo
      verify: (_) {
        verify(mockNodeRepository.upsertNode(argThat(
          predicate((n) =>
              n is Node && n.bleAddress == 'BB:CC:DD:EE:FF:00'),
        ))).called(1);
      },
    );
  });
}
