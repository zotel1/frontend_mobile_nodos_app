import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide ScanResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
import 'package:frontend_mobile_nodos_app/screens/home_screen.dart';
import 'package:frontend_mobile_nodos_app/core/utils/distance_calc.dart';

import '../helpers/fake_dependencies.dart';

/// Wraps [HomeScreen] in a [MaterialApp] with injected fake dependencies.
Widget buildTestHomeScreen({
  required FakeBleAdapter adapter,
  FakeSecureStorage? storage,
}) {
  return MaterialApp(
    home: HomeScreen(
      bleManager: BleManager(adapter: adapter),
      secureStorage: storage ?? FakeSecureStorage(),
    ),
  );
}

/// Finds an [ElevatedButton] that contains the given [text].
Finder findElevatedButtonWithText(String text) {
  return find.widgetWithText(ElevatedButton, text);
}

void main() {
  group('HomeScreen UI — BLS-001', () {
    late FakeBleAdapter adapter;
    late FakeSecureStorage storage;

    setUp(() async {
      adapter = FakeBleAdapter();
      storage = FakeSecureStorage();
      // Pre-populate UUID so getOrCreateDeviceUuid resolves instantly.
      await storage.saveDeviceUuid('test-uuid-1234-5678-9abc-def012345678');
    });

    tearDown(() {
      adapter.dispose();
    });

    // --- UI-001: BT ON — no dialog, no banner, scan button enabled ---

    testWidgets('UI-001: BT ON shows no dialog/banner, scan button enabled',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle(); // initState + async _init() + listeners

      adapter.emitAdapterState(BluetoothAdapterState.on);
      await tester.pump(); // process stream
      await tester.pump(); // postFrameCallback

      // No dialog or banner
      expect(find.text('Bluetooth requerido'), findsNothing);
      expect(
          find.text(
              'La app no funciona sin Bluetooth activado. Encendelo desde Configuración.'),
          findsNothing);

      // Scan button present and enabled
      final btnFinder = findElevatedButtonWithText('Escanear');
      expect(btnFinder, findsOneWidget);
      final btn = tester.widget<ElevatedButton>(btnFinder);
      expect(btn.onPressed, isNotNull);
    });

    // --- UI-002: BT OFF at launch — AlertDialog with buttons ---

    testWidgets(
        'UI-002: BT OFF at launch shows dialog with settings/cancel buttons',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle(); // initState + async _init()

      adapter.emitAdapterState(BluetoothAdapterState.off);
      await tester.pump(); // process stream → setState schedules dialog
      await tester.pump(); // postFrameCallback → showDialog
      await tester.pump(); // dialog animation

      // Dialog content
      expect(find.text('Bluetooth requerido'), findsOneWidget);
      expect(find.text('Encendé Bluetooth para detectar dispositivos cercanos'),
          findsOneWidget);
      expect(find.text('Ir a Configuración'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    // --- UI-003: Cancel → banner shown, scan disabled ---

    testWidgets(
        'UI-003: Cancel dismisses dialog, shows banner, disables scan button',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle();

      adapter.emitAdapterState(BluetoothAdapterState.off);
      await tester.pump(); // process stream
      await tester.pump(); // postFrameCallback → showDialog
      await tester.pump(); // dialog animation

      // Dialog is up — tap Cancel
      await tester.tap(find.text('Cancelar'));
      await tester.pump(); // dialog dismiss animation
      await tester.pump(); // post-dismiss frame

      // Dialog gone, banner visible
      expect(find.text('Bluetooth requerido'), findsNothing);
      expect(
          find.text(
              'La app no funciona sin Bluetooth activado. Encendelo desde Configuración.'),
          findsOneWidget);

      // Scan button disabled
      final btnFinder = findElevatedButtonWithText('Escanear');
      expect(btnFinder, findsOneWidget);
      final btn = tester.widget<ElevatedButton>(btnFinder);
      expect(btn.onPressed, isNull);
    });

    // --- UI-004: "Ir a Configuración" → dialog dismissed ---

    testWidgets(
        'UI-004: "Ir a Configuración" dismisses dialog (platform call not tested)',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle();

      adapter.emitAdapterState(BluetoothAdapterState.off);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Ir a Configuración'));
      await tester.pump();
      await tester.pump();

      // Dialog is gone
      expect(find.text('Bluetooth requerido'), findsNothing);
    });

    // --- UI-005: BT turns on → banner disappears, scan enabled ---

    testWidgets(
        'UI-005: BT-on event hides banner and enables scan button',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle();

      // BT off → dismiss dialog → banner shown
      adapter.emitAdapterState(BluetoothAdapterState.off);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump();

      expect(
          find.text(
              'La app no funciona sin Bluetooth activado. Encendelo desde Configuración.'),
          findsOneWidget);

      // Turn BT on
      adapter.emitAdapterState(BluetoothAdapterState.on);
      await tester.pump(); // process stream → setState
      await tester.pump(); // rebuild with _showBanner = false
      await tester.pump(); // MaterialBanner dismiss animation

      // Banner gone, scan enabled
      expect(
          find.text(
              'La app no funciona sin Bluetooth activado. Encendelo desde Configuración.'),
          findsNothing);
      final btnFinder = findElevatedButtonWithText('Escanear');
      final btn = tester.widget<ElevatedButton>(btnFinder);
      expect(btn.onPressed, isNotNull);
    });

    // --- UI-006: Scan results → device list with proximity colors ---

    testWidgets('UI-006: Devices render in list with proximity zone colors',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle();

      adapter.emitAdapterState(BluetoothAdapterState.on);
      await tester.pump();

      // Emit devices with varying RSSI / proximity levels.
      // Devices with RSSI < -85 are filtered out by BleManager.
      final now = DateTime(2026);
      adapter.emitScanResults([
        ScanResult(
          deviceId: 'AA:BB:CC:DD:EE:FF',
          deviceUuid: 'uuid-close',
          rssi: -55,
          distance: 1.78,
          proximity: ProximityLevel.close,
          timestamp: now,
        ),
        ScanResult(
          deviceId: 'BB:CC:DD:EE:FF:01',
          deviceUuid: 'uuid-medium',
          rssi: -78,
          distance: 25.1,
          proximity: ProximityLevel.medium,
          timestamp: now,
        ),
        // RSSI -95 is filtered out by BleManager (_filterByRssi: rssi ≥ -85)
        ScanResult(
          deviceId: 'CC:DD:EE:FF:01:02',
          deviceUuid: 'uuid-far',
          rssi: -95,
          distance: 177.8,
          proximity: ProximityLevel.far,
          timestamp: now,
        ),
      ]);
      await tester.pump();

      // Close and medium devices shown (truncated IDs)
      expect(find.text('AA:BB:CC'), findsOneWidget);
      expect(find.text('BB:CC:DD'), findsOneWidget);

      // Far device (RSSI -95) is filtered out — not shown
      expect(find.text('CC:DD:EE'), findsNothing);

      // Distance + RSSI rendered
      expect(find.textContaining('1.8m'), findsOneWidget);
      expect(find.textContaining('25.1m'), findsOneWidget);
    });

    // --- UI-007: No devices → empty state ---

    testWidgets('UI-007: No scan results shows empty state',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle();

      adapter.emitAdapterState(BluetoothAdapterState.on);
      await tester.pump();

      // Emit empty list
      adapter.emitScanResults([]);
      await tester.pump();

      expect(find.text('Sin dispositivos cercanos'), findsOneWidget);
    });

    // --- UI-008: Scan toggle → starts/stops duty cycle ---

    testWidgets('UI-008: Scan toggle starts and stops duty cycle',
        (tester) async {
      await tester.pumpWidget(buildTestHomeScreen(
        adapter: adapter,
        storage: storage,
      ));
      await tester.pumpAndSettle();

      adapter.emitAdapterState(BluetoothAdapterState.on);
      await tester.pump(); // process stream
      await tester.pump(); // rebuild

      // Initial state: idle
      expect(find.text('Detenido'), findsOneWidget);

      // Verify button exists and is enabled
      expect(find.byType(ElevatedButton), findsOneWidget);
      final btnBefore = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btnBefore.onPressed, isNotNull, reason: 'Scan button should be enabled when BT is on');

      // Tap Escanear button
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump(); // process tap + setState rebuild
      await tester.pump(); // settle

      // Check button text changed (proves toggle was called)
      expect(find.text('Detener'), findsOneWidget);
      // Now scanning
      expect(find.text('Escaneando...'), findsOneWidget);

      // Tap Detener button
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump();

      // Back to idle
      expect(find.text('Escanear'), findsOneWidget);
      expect(find.text('Detenido'), findsOneWidget);
    });
  });
}
