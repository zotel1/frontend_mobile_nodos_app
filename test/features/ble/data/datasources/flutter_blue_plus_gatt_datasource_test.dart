import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/ble_gatt_datasource.dart';
import 'package:frontend_mobile_nodos_app/features/ble/data/datasources/flutter_blue_plus_gatt_datasource.dart';

/// Verifica que [FlutterBluePlusGattDataSource] delegue correctamente
/// las operaciones connect, disconnect, isConnected y connectionState.
///
/// Usa inyección de funciones para evitar dependencia de la plataforma
/// FlutterBluePlus en tests unitarios (Extract-Before-Mock).
void main() {
  group('FlutterBluePlusGattDataSource', () {
    // ─────────────── connect ───────────────

    test('connect delega a la función inyectada con el remoteId correcto',
        () async {
      String? capturedRemoteId;
      int connectCallCount = 0;

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (remoteId) async {
          capturedRemoteId = remoteId;
          connectCallCount++;
        },
        disconnectFn: (_) async {},
        connectionStateFn: (_) => const Stream.empty(),
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      await datasource.connect('AA:BB:CC:DD:EE:FF');

      expect(capturedRemoteId, equals('AA:BB:CC:DD:EE:FF'));
      expect(connectCallCount, equals(1));
    });

    test('connect propaga excepciones de la función inyectada', () async {
      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async => throw Exception('Device not found'),
        disconnectFn: (_) async {},
        connectionStateFn: (_) => const Stream.empty(),
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      expect(
        () => datasource.connect('invalid-id'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Device not found'),
        )),
      );
    });

    // ─────────────── disconnect ───────────────

    test('disconnect delega a la función inyectada con el remoteId correcto',
        () async {
      String? capturedRemoteId;

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (remoteId) async {
          capturedRemoteId = remoteId;
        },
        connectionStateFn: (_) => const Stream.empty(),
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      await datasource.disconnect('11:22:33:44:55:66');

      expect(capturedRemoteId, equals('11:22:33:44:55:66'));
    });

    // ─────────────── isConnected ───────────────
    //
    // isConnected retorna el último estado conocido desde el mapa interno
    // _lastConnectionState. Este mapa se actualiza cuando connectionState()
    // emite — refleja el patrón de uso real: el BLoC se suscribe al stream
    // y usa isConnected para consultas síncronas posteriores.

    test('isConnected retorna true cuando connectionState emitió true', () async {
      final stateController = StreamController<bool>.broadcast();

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (_) => stateController.stream,
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      // Suscribirse al stream → actualiza el mapa interno
      datasource.connectionState('any-id').listen((_) {});
      stateController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = await datasource.isConnected('any-id');
      expect(result, isTrue);

      await stateController.close();
    });

    test('isConnected retorna false cuando connectionState emitió false',
        () async {
      final stateController = StreamController<bool>.broadcast();

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (_) => stateController.stream,
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      // Suscribirse al stream y emitir desconectado
      datasource.connectionState('any-id').listen((_) {});
      stateController.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = await datasource.isConnected('any-id');
      expect(result, isFalse);

      await stateController.close();
    });

    test('isConnected retorna false cuando connectionState nunca emitió',
        () async {
      final stateController = StreamController<bool>.broadcast();

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (_) => stateController.stream,
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      // No se llama a connectionState → el mapa está vacío → retorna false.
      final result = await datasource.isConnected('never-connected');
      expect(result, isFalse);

      await stateController.close();
    });

    // ─────────────── connectionState ───────────────

    test('connectionState retorna el stream inyectado para el remoteId',
        () async {
      String? capturedRemoteId;
      final stateController = StreamController<bool>.broadcast();

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (remoteId) {
          capturedRemoteId = remoteId;
          return stateController.stream;
        },
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      final stream = datasource.connectionState('device-abc');
      final received = <bool>[];

      final sub = stream.listen(received.add);
      stateController.add(true);
      stateController.add(false);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(capturedRemoteId, equals('device-abc'));
      expect(received, equals([true, false]));

      await sub.cancel();
      await stateController.close();
    });

    // ─────────────── discoverServices ───────────────
    //
    // T3.1: discoverServices retorna lista de BleServiceInfo.
    // T3.1: readCharacteristic retorna bytes cuando la característica existe.
    // T3.1: readCharacteristic retorna null cuando la característica no existe.

    test('discoverServices retorna lista de BleServiceInfo con el remoteId correcto',
        () async {
      String? capturedRemoteId;
      int callCount = 0;

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (_) => const Stream.empty(),
        discoverServicesFn: (remoteId) async {
          capturedRemoteId = remoteId;
          callCount++;
          return [
            const BleServiceInfo(
              uuid: '00001800-0000-1000-8000-00805f9b34fb',
              characteristicUuids: ['00002a00-0000-1000-8000-00805f9b34fb'],
            ),
          ];
        },
        readCharacteristicFn: (_, _) async => null,
      );

      final services = await datasource.discoverServices('AA:BB:CC:DD:EE:FF');

      expect(capturedRemoteId, equals('AA:BB:CC:DD:EE:FF'));
      expect(callCount, equals(1));
      expect(services.length, equals(1));
      expect(services.first.uuid, equals('00001800-0000-1000-8000-00805f9b34fb'));
      expect(services.first.characteristicUuids.length, equals(1));
    });

    test('readCharacteristic retorna bytes cuando la característica existe',
        () async {
      String? capturedRemoteId;
      String? capturedCharUuid;

      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (_) => const Stream.empty(),
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (remoteId, charUuid) async {
          capturedRemoteId = remoteId;
          capturedCharUuid = charUuid;
          return [0x7B, 0x22, 0x6E]; // bytes de {"n
        },
      );

      final result = await datasource.readCharacteristic(
        'AA:BB:CC:DD:EE:FF',
        '4fafc202-1fb5-459e-8fcc-c5c9c331914b',
      );

      expect(capturedRemoteId, equals('AA:BB:CC:DD:EE:FF'));
      expect(capturedCharUuid, equals('4fafc202-1fb5-459e-8fcc-c5c9c331914b'));
      expect(result, isNotNull);
      expect(result!.length, equals(3));
      expect(result[0], equals(0x7B));
    });

    test('readCharacteristic retorna null cuando la característica no existe',
        () async {
      final datasource = FlutterBluePlusGattDataSource.test(
        connectFn: (_) async {},
        disconnectFn: (_) async {},
        connectionStateFn: (_) => const Stream.empty(),
        discoverServicesFn: (_) async => [],
        readCharacteristicFn: (_, _) async => null,
      );

      final result = await datasource.readCharacteristic(
        'AA:BB:CC:DD:EE:FF',
        'nonexistent-uuid',
      );

      expect(result, isNull);
    });
  });
}
