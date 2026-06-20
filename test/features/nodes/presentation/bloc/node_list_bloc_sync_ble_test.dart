import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/repositories/node_repository.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/presentation/bloc/node_list_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

@GenerateNiceMocks([
  MockSpec<ObserveNodes>(),
  MockSpec<UpdateNodeMetadata>(),
  MockSpec<NodeRepository>(),
])
import 'node_list_bloc_sync_ble_test.mocks.dart';

/// Tests unitarios para el evento SyncBleDevices y su handler en NodeListBloc.
///
/// Verifica que el puente BLE→Node:
/// 1. Convierta BleDevice → Node correctamente (mapeo deviceId→bleAddress,
///    rssi→rssiHistory, firstSeen preservado para nodos existentes).
/// 2. Deduplique por bleAddress (mismo deviceId actualiza, no duplica).
/// 3. Ignore dispositivos con RSSI inválido (>= 0).
/// 4. Limite rssiHistory a 20 entradas (dropeando las más antiguas).
/// 5. Maneje lista vacía sin errores.
void main() {
  late MockObserveNodes mockObserveNodes;
  late MockUpdateNodeMetadata mockUpdateNodeMetadata;
  late MockNodeRepository mockNodeRepository;

  final now = DateTime(2026, 6, 19);

  /// Crea un BleDevice de prueba con los valores mínimos necesarios.
  BleDevice testDevice({
    required String id,
    required int rssi,
    DateTime? timestamp,
  }) {
    return BleDevice(
      deviceId: id,
      rssi: rssi,
      distance: 5.0,
      proximity: ProximityLevel.medium,
      timestamp: timestamp ?? now,
    );
  }

  setUp(() {
    mockObserveNodes = MockObserveNodes();
    mockUpdateNodeMetadata = MockUpdateNodeMetadata();
    mockNodeRepository = MockNodeRepository();

    // Tabula rasa: watchNodes emite lista vacía por defecto.
    when(mockObserveNodes.call())
        .thenAnswer((_) => Stream.value([]));
    when(mockNodeRepository.upsertNode(any)).thenAnswer((_) async {});
  });

  group('SyncBleDevices — BLE → Node bridge', () {
    // ── Escenario 1: Primer escaneo puebla nodos nuevos ──
    blocTest<NodeListBloc, NodeListState>(
      'convierte 2 BleDevice en Node y llama upsertNode 2 veces',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        testDevice(id: 'AA:BB:CC:DD:EE:01', rssi: -60),
        testDevice(id: 'AA:BB:CC:DD:EE:02', rssi: -75),
      ])),
      // El handler no emite estado directamente — watchNodes emite
      // después del upsert. Verificamos que upsertNode fue llamado.
      verify: (_) {
        verify(mockNodeRepository.upsertNode(argThat(
          predicate<Node>((n) =>
              n.bleAddress == 'AA:BB:CC:DD:EE:01' &&
              n.rssiHistory.contains(-60)),
        ))).called(1);
        verify(mockNodeRepository.upsertNode(argThat(
          predicate<Node>((n) =>
              n.bleAddress == 'AA:BB:CC:DD:EE:02' &&
              n.rssiHistory.contains(-75)),
        ))).called(1);
      },
    );

    // ── Escenario 2: Ignora RSSI >= 0 (señal inválida) ──
    blocTest<NodeListBloc, NodeListState>(
      'ignora BleDevice con RSSI >= 0 (señal inválida)',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        testDevice(id: 'AA:BB:CC:DD:EE:01', rssi: -60),
        testDevice(id: 'FF:EE:DD:CC:BB:AA', rssi: 0),
        testDevice(id: '11:22:33:44:55:66', rssi: 127),
      ])),
      verify: (_) {
        // Solo el primer dispositivo (RSSI=-60) debe persistirse.
        verify(mockNodeRepository.upsertNode(argThat(
          predicate<Node>((n) => n.bleAddress == 'AA:BB:CC:DD:EE:01'),
        ))).called(1);
        // Los otros dos NO deben llamar upsertNode.
        verifyNever(mockNodeRepository.upsertNode(argThat(
          predicate<Node>((n) => n.bleAddress == 'FF:EE:DD:CC:BB:AA'),
        )));
        verifyNever(mockNodeRepository.upsertNode(argThat(
          predicate<Node>((n) => n.bleAddress == '11:22:33:44:55:66'),
        )));
      },
    );

    // ── Escenario 3: Dedup — mismo deviceId actualiza, no duplica ──
    blocTest<NodeListBloc, NodeListState>(
      'dedup por bleAddress: mismo deviceId actualiza rssiHistory, no duplica',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        testDevice(id: 'AA:BB:CC:DD:EE:FF', rssi: -60),
        testDevice(id: 'AA:BB:CC:DD:EE:FF', rssi: -55),
      ])),
      verify: (_) {
        // El handler deduplica por deviceId dentro del mismo batch:
        // una sola llamada a upsertNode con rssiHistory combinado [-60, -55].
        final captured = verify(mockNodeRepository.upsertNode(captureAny))
            .captured;
        expect(captured, hasLength(1));
        final node = captured.single as Node;
        expect(node.bleAddress, 'AA:BB:CC:DD:EE:FF');
        expect(node.rssiHistory, [-60, -55]);
        expect(node.name, isNull);
        expect(node.color, isNull);
      },
    );

    // ── Escenario 4: rssiHistory limitado a 20 entradas ──
    blocTest<NodeListBloc, NodeListState>(
      'rssiHistory conserva máximo 20 entradas (dropea las más antiguas)',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) {
        // Simula 25 actualizaciones consecutivas del mismo dispositivo.
        // Cada una con RSSI distinto para verificar que solo las últimas
        // 20 se conservan.
        final devices = List.generate(
          25,
          (i) => testDevice(id: 'AA:BB:CC:DD:EE:01', rssi: -(60 + i)),
        );
        bloc.add(SyncBleDevices(devices));
      },
      verify: (_) {
        // La última llamada a upsertNode debe tener rssiHistory con
        // exactamente 20 entradas (las más recientes: índices 5 a 24).
        final captured = verify(mockNodeRepository.upsertNode(captureAny))
            .captured;
        // La última llamada tiene el Node con rssiHistory ya limitado.
        final lastCaptured = captured.last as Node;
        expect(lastCaptured.rssiHistory.length, lessThanOrEqualTo(20));
        // El primer elemento debe ser -(60+5) = -65 (dropeó los 5 primeros).
        expect(lastCaptured.rssiHistory.first, equals(-65));
        // El último elemento debe ser -(60+24) = -84.
        expect(lastCaptured.rssiHistory.last, equals(-84));
      },
    );

    // ── Escenario 5: Lista vacía → no-op ──
    blocTest<NodeListBloc, NodeListState>(
      'lista vacía no emite estado ni llama al repositorio',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(const SyncBleDevices([])),
      // Sin dispositivos: no debe llamar a upsertNode.
      verify: (_) {
        verifyNever(mockNodeRepository.upsertNode(any));
      },
    );

    // ── T1.6: Mapeo de advName → suggestedName y deviceType ──
    // QUÉ: Verifica que el BLoC mapea advName de BleDevice a suggestedName
    // del Node y deviceType de BleDevice a deviceType del Node.
    // POR QUÉ: Phase 4 identity enrichment — los nombres sugeridos y tipos
    // de dispositivo se propagan desde el advertisement al nodo persistido.

    blocTest<NodeListBloc, NodeListState>(
      'T1.6: mapea advName → suggestedName en el Node upsertado',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:01',
          rssi: -60,
          distance: 3.0,
          proximity: ProximityLevel.close,
          timestamp: now,
          advName: 'AirPods Pro',
        ),
      ])),
      verify: (_) {
        final captured = verify(mockNodeRepository.upsertNode(captureAny))
            .captured;
        expect(captured, hasLength(1));
        final node = captured.single as Node;
        expect(node.suggestedName, 'AirPods Pro');
      },
    );

    blocTest<NodeListBloc, NodeListState>(
      'T1.6: mapea deviceType → deviceType en el Node upsertado',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:02',
          rssi: -65,
          distance: 5.0,
          proximity: ProximityLevel.medium,
          timestamp: now,
          deviceType: 'Reloj/Fitness',
        ),
      ])),
      verify: (_) {
        final captured = verify(mockNodeRepository.upsertNode(captureAny))
            .captured;
        final node = captured.single as Node;
        expect(node.deviceType, 'Reloj/Fitness');
      },
    );

    blocTest<NodeListBloc, NodeListState>(
      'T1.6: advName vacío → suggestedName null en el Node',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:03',
          rssi: -70,
          distance: 8.0,
          proximity: ProximityLevel.medium,
          timestamp: now,
          advName: '',
        ),
      ])),
      verify: (_) {
        final captured = verify(mockNodeRepository.upsertNode(captureAny))
            .captured;
        final node = captured.single as Node;
        expect(node.suggestedName, isNull);
      },
    );

    blocTest<NodeListBloc, NodeListState>(
      'T1.6: mapea ambos campos simultáneamente',
      build: () => NodeListBloc(
        observeNodes: mockObserveNodes,
        updateNodeMetadata: mockUpdateNodeMetadata,
        nodeRepository: mockNodeRepository,
      ),
      act: (bloc) => bloc.add(SyncBleDevices([
        BleDevice(
          deviceId: 'AA:BB:CC:DD:EE:04',
          rssi: -55,
          distance: 2.0,
          proximity: ProximityLevel.close,
          timestamp: now,
          advName: 'Galaxy Watch',
          deviceType: 'Reloj/Fitness',
        ),
      ])),
      verify: (_) {
        final captured = verify(mockNodeRepository.upsertNode(captureAny))
            .captured;
        final node = captured.single as Node;
        expect(node.suggestedName, 'Galaxy Watch');
        expect(node.deviceType, 'Reloj/Fitness');
      },
    );
  });
}
