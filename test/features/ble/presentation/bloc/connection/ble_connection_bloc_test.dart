import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';

@GenerateNiceMocks([MockSpec<BleGattDataSource>()])
import 'ble_connection_bloc_test.mocks.dart';

void main() {
  late MockBleGattDataSource mockDatasource;
  late StreamController<bool> stateController;

  setUp(() {
    mockDatasource = MockBleGattDataSource();
    stateController = StreamController<bool>.broadcast();
  });

  tearDown(() async {
    await stateController.close();
  });

  group('BleConnectionBloc', () {
    // ─────────── Estado inicial ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionInitial como estado inicial',
      build: () => BleConnectionBloc(gatt: mockDatasource),
      verify: (bloc) => expect(bloc.state, isA<BleConnectionInitial>()),
    );

    // ─────────── ConnectToDevice ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnecting → BleConnected al conectar exitosamente',
      build: () {
        when(mockDatasource.connect(any)).thenAnswer((_) async {});
        when(mockDatasource.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        // Emitir conectado después de la construcción del bloc
        Future.microtask(() => stateController.add(true));
        return BleConnectionBloc(gatt: mockDatasource);
      },
      act: (bloc) => bloc.add(const ConnectToDevice('AA:BB:CC:DD:EE:FF')),
      expect: () => [
        isA<BleConnecting>().having(
          (s) => s.remoteId,
          'remoteId',
          equals('AA:BB:CC:DD:EE:FF'),
        ),
        isA<BleConnected>().having(
          (s) => s.remoteId,
          'remoteId',
          equals('AA:BB:CC:DD:EE:FF'),
        ),
      ],
      verify: (_) {
        verify(mockDatasource.connect('AA:BB:CC:DD:EE:FF')).called(1);
      },
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnecting → BleConnectionError cuando connect() lanza excepción',
      build: () {
        when(mockDatasource.connect(any))
            .thenThrow(Exception('Device unreachable'));
        when(mockDatasource.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        return BleConnectionBloc(gatt: mockDatasource);
      },
      act: (bloc) => bloc.add(const ConnectToDevice('BB:CC:DD:EE:FF:00')),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnectionError>()
            .having((s) => s.message, 'message', contains('Device unreachable'))
            .having((s) => s.retryable, 'retryable', isTrue),
      ],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionError con retryable=true ante timeout',
      build: () {
        when(mockDatasource.connect(any))
            .thenThrow(TimeoutException('Connection timed out'));
        when(mockDatasource.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        return BleConnectionBloc(gatt: mockDatasource);
      },
      act: (bloc) => bloc.add(const ConnectToDevice('timeout-device')),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnectionError>().having(
          (s) => s.retryable,
          'retryable',
          isTrue,
        ),
      ],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionError con retryable=false ante error no recuperable',
      build: () {
        when(mockDatasource.connect(any))
            .thenThrow(StateError('Bluetooth is disabled'));
        when(mockDatasource.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        return BleConnectionBloc(gatt: mockDatasource);
      },
      act: (bloc) => bloc.add(const ConnectToDevice('bt-off-device')),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnectionError>().having(
          (s) => s.retryable,
          'retryable',
          isFalse,
        ),
      ],
    );

    // ─────────── DisconnectDevice ───────────

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionInitial al desconectar desde BleConnected',
      build: () {
        when(mockDatasource.disconnect(any)).thenAnswer((_) async {});
        return BleConnectionBloc(gatt: mockDatasource);
      },
      seed: () => const BleConnected(remoteId: 'AA:BB:CC:DD:EE:FF'),
      act: (bloc) => bloc.add(const DisconnectDevice('AA:BB:CC:DD:EE:FF')),
      expect: () => [isA<BleConnectionInitial>()],
      verify: (_) {
        verify(mockDatasource.disconnect('AA:BB:CC:DD:EE:FF')).called(1);
      },
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'emite BleConnectionInitial al desconectar desde BleConnectionError',
      build: () {
        when(mockDatasource.disconnect(any)).thenAnswer((_) async {});
        return BleConnectionBloc(gatt: mockDatasource);
      },
      seed: () => const BleConnectionError(
        message: 'prev error',
        retryable: true,
      ),
      act: (bloc) => bloc.add(const DisconnectDevice('any-id')),
      expect: () => [isA<BleConnectionInitial>()],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'no emite nada al desconectar desde BleConnectionInitial (ya está desconectado)',
      build: () {
        when(mockDatasource.disconnect(any)).thenAnswer((_) async {});
        return BleConnectionBloc(gatt: mockDatasource);
      },
      act: (bloc) => bloc.add(const DisconnectDevice('any-id')),
      expect: () => [],
    );

    // ─────────── T-PR1-001: _ConnectionStateChanged handler (RED) ───────────
    // QUÉ: verifica que cuando el stream de conexión emite false (desconexión),
    // el BLoC emite BleConnectionInitial en lugar de ignorarlo.
    // POR QUÉ: actualmente la suscripción solo maneja connected==true.
    // Si el periférico se desconecta (connected==false), el BLoC no reacciona
    // y el estado queda como BleConnected fantasma, causando que la UI muestre
    // "Conectado" cuando en realidad no hay conexión.

    blocTest<BleConnectionBloc, BleConnectionState>(
      'T-PR1-001: emite BleConnectionInitial cuando el stream emite false (desconexión)',
      build: () {
        when(mockDatasource.connect(any)).thenAnswer((_) async {});
        when(mockDatasource.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        // Emitir false DESPUÉS de que connect() retorne y la suscripción
        // esté configurada. Usamos un delay corto para asegurar que
        // _onConnect ya configuró la suscripción al stream.
        Future.delayed(const Duration(milliseconds: 20), () {
          stateController.add(false);
        });
        return BleConnectionBloc(gatt: mockDatasource);
      },
      seed: () => const BleConnected(remoteId: 'AA:BB:CC:DD:EE:FF'),
      act: (bloc) => bloc.add(const ConnectToDevice('AA:BB:CC:DD:EE:FF')),
      // wait asegura que blocTest espere a que el timer dispare y el
      // BLoC procese el evento _ConnectionStateChanged(false).
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
        isA<BleConnectionInitial>(),
      ],
    );

    blocTest<BleConnectionBloc, BleConnectionState>(
      'T-PR1-001: _ConnectionStateChanged no crashea con StateError',
      build: () {
        when(mockDatasource.connect(any)).thenAnswer((_) async {});
        when(mockDatasource.connectionState(any))
            .thenAnswer((_) => stateController.stream);
        Future.delayed(const Duration(milliseconds: 20), () {
          stateController.add(false);
        });
        return BleConnectionBloc(gatt: mockDatasource);
      },
      seed: () => const BleConnected(remoteId: 'FF:EE:DD:CC:BB:AA'),
      act: (bloc) => bloc.add(const ConnectToDevice('FF:EE:DD:CC:BB:AA')),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<BleConnecting>(),
        isA<BleConnected>(),
        isA<BleConnectionInitial>(),
      ],
    );
  });
}
