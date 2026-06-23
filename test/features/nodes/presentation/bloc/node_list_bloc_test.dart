import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
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
      'emits [NodeListLoaded] when LoadNodes is added '
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
        isA<NodeListLoaded>().having(
          (s) => s.nodes,
          'nodes',
          equals(testNodes),
        ),
      ],
    );

    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListEmpty] when LoadNodes is added '
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
      'handles RefreshNodes as no-op — stream already reactive',
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
      // La suscripción ya es reactiva: no se emite nada nuevo.
      expect: () => <NodeListState>[],
    );

    blocTest<NodeListBloc, NodeListState>(
      'handles RefreshNodes as no-op from empty state',
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
      // La suscripción ya es reactiva: no se emite nada nuevo.
      expect: () => <NodeListState>[],
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
      // _ensureSubscription crea el watcher sin emitir loading.
      // El stream Drift emite reactivamente la lista actualizada.
      expect: () => [
        isA<NodeListLoaded>().having(
          (s) => s.nodes.length,
          'nodes.length',
          2, // testNodes tiene 2 nodos
        ),
      ],
    );
  });

  // ─── PR1.8: ClearNodes, UpdateNodeName, UpdateNodeColor ──────
  // QUÉ: ClearNodes emite NodeListEmpty tras limpiar la BD.
  // UpdateNodeName/Color emiten NodeListLoaded con el nodo actualizado.
  // POR QUÉ: pipeline para limpiar al apagar BT (R5.17) y para
  // metadata del bottom sheet de identidad (R5.5-R5.7).

  group('ClearNodes', () {
    blocTest<NodeListBloc, NodeListState>(
      'ClearNodes llama a clearAllNodes del repositorio',
      seed: () => NodeListLoaded(testNodes),
      build: () {
        when(mockNodeRepository.clearAllNodes()).thenAnswer((_) async {});
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(const ClearNodes()),
      // El stream reactivo emitirá la lista vacía automáticamente.
      expect: () => <NodeListState>[],
      verify: (_) {
        verify(mockNodeRepository.clearAllNodes()).called(1);
      },
    );
  });

  group('UpdateNodeName', () {
    blocTest<NodeListBloc, NodeListState>(
      'UpdateNodeName llama a updateNodeMetadata y el stream reacciona solo',
      build: () {
        // updateNodeMetadata devuelve Right(null).
        when(mockUpdateNodeMetadata(any))
            .thenAnswer((_) async => const Right(null));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(const UpdateNodeName(1, 'Nuevo Nombre')),
      // El stream reactivo emitirá la lista actualizada automáticamente.
      expect: () => <NodeListState>[],
      verify: (_) {
        verify(mockUpdateNodeMetadata(
          argThat(
            predicate<UpdateNodeMetadataParams>((p) =>
                p.id == 1 && p.name == 'Nuevo Nombre'),
          ),
        )).called(1);
      },
    );
  });

  group('UpdateNodeColor', () {
    blocTest<NodeListBloc, NodeListState>(
      'UpdateNodeColor llama a updateNodeMetadata y el stream reacciona solo',
      build: () {
        when(mockUpdateNodeMetadata(any))
            .thenAnswer((_) async => const Right(null));
        return NodeListBloc(
          observeNodes: mockObserveNodes,
          updateNodeMetadata: mockUpdateNodeMetadata,
          nodeRepository: mockNodeRepository,
        );
      },
      act: (bloc) => bloc.add(const UpdateNodeColor(2, '#FF0000')),
      // El stream reactivo emitirá la lista actualizada automáticamente.
      expect: () => <NodeListState>[],
      verify: (_) {
        verify(mockUpdateNodeMetadata(
          argThat(
            predicate<UpdateNodeMetadataParams>((p) =>
                p.id == 2 && p.color == '#FF0000'),
          ),
        )).called(1);
      },
    );
  });
}
