import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide ScanResult;
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_mobile_nodos_app/ble/ble_manager.dart';
import 'package:frontend_mobile_nodos_app/main.dart';

import 'helpers/fake_dependencies.dart';

void main() {
  testWidgets('NodosApp renders HomeScreen with title and scan button',
      (tester) async {
    final adapter = FakeBleAdapter();
    final storage = FakeSecureStorage();
    await storage.saveDeviceUuid('test-uuid-1234-5678');

    await tester.pumpWidget(NodosApp(
      bleManager: BleManager(adapter: adapter),
      secureStorage: storage,
    ));
    await tester.pumpAndSettle();

    adapter.emitAdapterState(BluetoothAdapterState.on);
    await tester.pump();
    await tester.pump();

    // App renders with title and scan button
    expect(find.text('Nodos'), findsOneWidget);
    expect(find.text('Escanear'), findsOneWidget);

    adapter.dispose();
  });
}
