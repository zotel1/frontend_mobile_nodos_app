import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';

// Will be created after writing this test
// ignore: depend_on_referenced_packages
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/pages/home_page.dart';

@GenerateNiceMocks([MockSpec<NodeListBloc>(), MockSpec<BleBloc>()])
import 'home_page_test.mocks.dart';

Node _testNode(String addr) => Node(
      id: 1,
      bleAddress: addr,
      name: 'Node $addr',
      firstSeen: DateTime(2026, 1, 1),
      lastSeen: DateTime(2026, 6, 18),
      rssiHistory: const [-50],
    );

Widget _pumpHomePage({
  required NodeListState nodeListState,
  BleState bleState = const BleStopped(),
}) {
  final mockNodeListBloc = MockNodeListBloc();
  final mockBleBloc = MockBleBloc();

  when(mockNodeListBloc.state).thenReturn(nodeListState);
  when(mockNodeListBloc.stream)
      .thenAnswer((_) => Stream.value(nodeListState));
  when(mockBleBloc.state).thenReturn(bleState);
  when(mockBleBloc.stream).thenAnswer((_) => Stream.value(bleState));

  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
        BlocProvider<BleBloc>.value(value: mockBleBloc),
      ],
      child: const HomePage(),
    ),
  );
}

void main() {
  group('HomePage', () {
    testWidgets('shows CircularProgressIndicator when loading',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListLoading(),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows ListView with NodeTile when loaded', (tester) async {
      final nodes = [
        _testNode('AA:BB:CC:DD:EE:01'),
        _testNode('AA:BB:CC:DD:EE:02'),
      ];
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: NodeListLoaded(nodes),
      ));

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Node AA:BB:CC:DD:EE:01'), findsOneWidget);
      expect(find.text('Node AA:BB:CC:DD:EE:02'), findsOneWidget);
    });

    testWidgets('shows empty state text when no nodes', (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListEmpty(),
      ));

      expect(find.text('No se encontraron nodos'), findsOneWidget);
    });

    testWidgets('shows error message when error state', (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListError('Something went wrong'),
      ));

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('AppBar has title Nodos and settings icon', (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListLoaded([]),
      ));

      expect(find.text('Nodos'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('FAB toggles scan — dispatches StartScan when stopped',
        (tester) async {
      final mockBleBloc = MockBleBloc();
      final mockNodeListBloc = MockNodeListBloc();

      when(mockBleBloc.state).thenReturn(const BleStopped());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleStopped()));
      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      verify(mockBleBloc.add(const StartScan())).called(1);
    });

    testWidgets('FAB toggles scan — dispatches StopScan when scanning',
        (tester) async {
      final mockBleBloc = MockBleBloc();
      final mockNodeListBloc = MockNodeListBloc();

      when(mockBleBloc.state).thenReturn(const BleScanning());
      when(mockBleBloc.stream)
          .thenAnswer((_) => Stream.value(const BleScanning()));
      when(mockNodeListBloc.state).thenReturn(const NodeListLoaded([]));
      when(mockNodeListBloc.stream)
          .thenAnswer((_) => Stream.value(const NodeListLoaded([])));

      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NodeListBloc>.value(value: mockNodeListBloc),
            BlocProvider<BleBloc>.value(value: mockBleBloc),
          ],
          child: const HomePage(),
        ),
      ));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      verify(mockBleBloc.add(const StopScan())).called(1);
    });

    testWidgets('shows BluetoothOffBanner when Bluetooth is off',
        (tester) async {
      await tester.pumpWidget(_pumpHomePage(
        nodeListState: const NodeListLoaded([]),
        bleState: const BluetoothOff(),
      ));

      // Verify the BluetoothOffBanner text is shown.
      expect(find.textContaining('Bluetooth desactivado'), findsOneWidget);
    });
  });
}
