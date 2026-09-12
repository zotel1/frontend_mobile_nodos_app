import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/node_detail_page.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/presentation/bloc/user_bloc.dart';

@GenerateNiceMocks([
  MockSpec<NodeListBloc>(),
  MockSpec<UserBloc>(),
  MockSpec<BleConnectionBloc>(),
])
import 'node_detail_page_test.mocks.dart';

void main() {
  provideDummy<BleConnectionState>(const BleConnectionInitial());

  final testNode = Node(
    id: 1,
    bleAddress: 'AA:BB:CC:DD:EE:FF',
    name: 'Mi Dispositivo',
    firstSeen: DateTime(2026, 1, 1),
    lastSeen: DateTime(2026, 6, 19),
    rssiHistory: const [-45],
    suggestedName: 'Dispositivo Anunciado',
    deviceType: 'Auriculares',
    connectable: true,
    isSelf: false,
  );

  UserLoaded loadedUser({int? localNodeId = 99}) {
    return UserLoaded(
      User(
        id: 42,
        uuid: 'test-uuid',
        name: 'Usuario',
        color: '#2196F3',
        deviceType: 'android',
        createdAt: DateTime(2026, 1, 1),
        localNodeId: localNodeId,
      ),
    );
  }

  Widget buildTestWidget({
    required Node node,
    required MockNodeListBloc nodeListBloc,
    required MockUserBloc userBloc,
    required MockBleConnectionBloc connectionBloc,
  }) {
    when(nodeListBloc.state).thenReturn(NodeListLoaded([node]));

    when(
      nodeListBloc.stream,
    ).thenAnswer((_) => Stream.value(NodeListLoaded([node])));

    when(connectionBloc.state).thenReturn(const BleConnectionInitial());

    when(
      connectionBloc.stream,
    ).thenAnswer((_) => Stream.value(const BleConnectionInitial()));

    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<NodeListBloc>.value(value: nodeListBloc),
          BlocProvider<UserBloc>.value(value: userBloc),
          BlocProvider<BleConnectionBloc>.value(value: connectionBloc),
        ],
        child: NodeDetailPage(id: node.id!),
      ),
    );
  }

  group('NodeDetailPage', () {
    testWidgets(
      'BUG-004: NodeDetailPage sin callback externo muestra Enlazar para nodo remoto conectable',
      (tester) async {
        final mockNodeListBloc = MockNodeListBloc();
        final mockUserBloc = MockUserBloc();
        final mockConnectionBloc = MockBleConnectionBloc();

        final userState = loadedUser();

        when(mockUserBloc.state).thenReturn(userState);
        when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

        await tester.pumpWidget(
          buildTestWidget(
            node: testNode,
            nodeListBloc: mockNodeListBloc,
            userBloc: mockUserBloc,
            connectionBloc: mockConnectionBloc,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Mi Dispositivo'), findsAtLeast(1));

        await tester.drag(find.byType(ListView), const Offset(0, -400));

        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Enlazar'), findsOneWidget);
        expect(find.byIcon(Icons.link), findsOneWidget);
      },
    );

    testWidgets(
      'BUG-004: al tocar Enlazar despacha ConnectToDevice con User.localNodeId',
      (tester) async {
        final mockNodeListBloc = MockNodeListBloc();
        final mockUserBloc = MockUserBloc();
        final mockConnectionBloc = MockBleConnectionBloc();

        final userState = loadedUser(localNodeId: 99);

        when(mockUserBloc.state).thenReturn(userState);
        when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

        await tester.pumpWidget(
          buildTestWidget(
            node: testNode,
            nodeListBloc: mockNodeListBloc,
            userBloc: mockUserBloc,
            connectionBloc: mockConnectionBloc,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.drag(find.byType(ListView), const Offset(0, -400));

        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Enlazar'), findsOneWidget);

        await tester.tap(find.text('Enlazar'));

        await tester.pump();

        verify(
          mockConnectionBloc.add(
            argThat(
              predicate<BleConnectionEvent>(
                (event) =>
                    event is ConnectToDevice &&
                    event.remoteId == 'AA:BB:CC:DD:EE:FF' &&
                    event.myNodeId == 99,
              ),
            ),
          ),
        ).called(1);
      },
    );

    testWidgets('BUG-004: no usa User.id como myNodeId', (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockUserBloc = MockUserBloc();
      final mockConnectionBloc = MockBleConnectionBloc();

      final userState = loadedUser(localNodeId: 99);

      when(mockUserBloc.state).thenReturn(userState);
      when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

      await tester.pumpWidget(
        buildTestWidget(
          node: testNode,
          nodeListBloc: mockNodeListBloc,
          userBloc: mockUserBloc,
          connectionBloc: mockConnectionBloc,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(find.byType(ListView), const Offset(0, -400));

      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Enlazar'));

      await tester.pump();

      verifyNever(
        mockConnectionBloc.add(
          argThat(
            predicate<BleConnectionEvent>(
              (event) => event is ConnectToDevice && event.myNodeId == 42,
            ),
          ),
        ),
      );
    });

    testWidgets('no muestra Enlazar para self-node', (tester) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockUserBloc = MockUserBloc();
      final mockConnectionBloc = MockBleConnectionBloc();

      final userState = loadedUser();

      when(mockUserBloc.state).thenReturn(userState);
      when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

      final selfNode = testNode.copyWith(isSelf: true);

      await tester.pumpWidget(
        buildTestWidget(
          node: selfNode,
          nodeListBloc: mockNodeListBloc,
          userBloc: mockUserBloc,
          connectionBloc: mockConnectionBloc,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(find.byType(ListView), const Offset(0, -400));

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enlazar'), findsNothing);
    });

    testWidgets('no muestra Enlazar cuando el nodo no es conectable', (
      tester,
    ) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockUserBloc = MockUserBloc();
      final mockConnectionBloc = MockBleConnectionBloc();

      final userState = loadedUser();

      when(mockUserBloc.state).thenReturn(userState);
      when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

      final nonConnectableNode = testNode.copyWith(connectable: false);

      await tester.pumpWidget(
        buildTestWidget(
          node: nonConnectableNode,
          nodeListBloc: mockNodeListBloc,
          userBloc: mockUserBloc,
          connectionBloc: mockConnectionBloc,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(find.byType(ListView), const Offset(0, -400));

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enlazar'), findsNothing);
    });

    testWidgets('no despacha conexión cuando User.localNodeId es null', (
      tester,
    ) async {
      final mockNodeListBloc = MockNodeListBloc();
      final mockUserBloc = MockUserBloc();
      final mockConnectionBloc = MockBleConnectionBloc();

      final userState = loadedUser(localNodeId: null);

      when(mockUserBloc.state).thenReturn(userState);
      when(mockUserBloc.stream).thenAnswer((_) => Stream.value(userState));

      await tester.pumpWidget(
        buildTestWidget(
          node: testNode,
          nodeListBloc: mockNodeListBloc,
          userBloc: mockUserBloc,
          connectionBloc: mockConnectionBloc,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(find.byType(ListView), const Offset(0, -400));

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enlazar'), findsOneWidget);

      await tester.tap(find.text('Enlazar'));

      await tester.pump();

      verifyNever(mockConnectionBloc.add(any));
    });
  });
}
