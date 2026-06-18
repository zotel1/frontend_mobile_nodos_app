import 'package:flutter/material.dart';

import 'ble/ble_manager.dart';
import 'screens/home_screen.dart';
import 'services/secure_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final bleAdapter = FlutterBluePlusAdapter();
  final bleManager = BleManager(adapter: bleAdapter);
  final secureStorage = DefaultSecureStorage();

  runApp(NodosApp(
    bleManager: bleManager,
    secureStorage: secureStorage,
  ));
}

/// Root widget of the Nodos application.
class NodosApp extends StatelessWidget {
  final BleManager? _bleManager;
  final SecureStorage? _secureStorage;

  const NodosApp({
    super.key,
    this._bleManager,
    this._secureStorage,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nodos',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomeScreen(
        bleManager: _bleManager ?? BleManager(),
        secureStorage: _secureStorage ?? DefaultSecureStorage(),
      ),
    );
  }
}
