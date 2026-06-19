import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';

@GenerateNiceMocks([MockSpec<ObserveNodes>(), MockSpec<UpdateNodeMetadata>()])
import 'node_list_bloc_test.mocks.dart';

void main() {
  late MockObserveNodes mockObserveNodes;
  late MockUpdateNodeMetadata mockUpdateNodeMetadata;

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
  });

  group('NodeListBloc', () {
    blocTest<NodeListBloc, NodeListState>(
      'emits [NodeListInitial] as initial state',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
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
        );
      },
      act: (bloc) => bloc.add(RefreshNodes()),
      expect: () => [
        isA<NodeListLoading>(),
        isA<NodeListEmpty>(),
      ],
    );
  });
}
