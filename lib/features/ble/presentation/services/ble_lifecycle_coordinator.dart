import 'dart:async';

import 'package:flutter/material.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/services/active_graph_exchange_service.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/services/live_graph_sync_service.dart';

/// Centraliza la invalidación del runtime BLE.
///
/// `connections` no participa de este cleanup: representa LINKED persistente.
/// En cambio, el scan, las conexiones GATT, el grafo activo y
/// `remote_relations` representan estado de la ejecución actual.
class BleLifecycleCoordinator {
  final BleRepository _bleRepository;
  final RemoteRelationRepository _remoteRelationRepository;
  final ActiveGraphExchangeService _activeGraphExchange;
  final BleBloc _bleBloc;
  final BleConnectionBloc _connectionBloc;
  final LiveGraphSyncService? _liveGraphSync;

  StreamSubscription<bool>? _adapterSubscription;
  bool _cleanupInProgress = false;
  bool? _lastAdapterState;

  BleLifecycleCoordinator({
    required BleRepository bleRepository,
    required RemoteRelationRepository remoteRelationRepository,
    required ActiveGraphExchangeService activeGraphExchange,
    required BleBloc bleBloc,
    required BleConnectionBloc connectionBloc,
    LiveGraphSyncService? liveGraphSync,
  }) : _bleRepository = bleRepository,
       _remoteRelationRepository = remoteRelationRepository,
       _activeGraphExchange = activeGraphExchange,
       _bleBloc = bleBloc,
       _connectionBloc = connectionBloc,
       _liveGraphSync = liveGraphSync;

  Future<void> initialize() async {
    _liveGraphSync?.start();
    // Los snapshots no sobreviven una ejecución: no se pueden considerar
    // activos sin una conexión GATT observada en esta ejecución.
    await _clearAllRemoteSnapshots();

    final firstAdapterState = Completer<bool>();
    _adapterSubscription = _bleRepository.bluetoothState.listen((isOn) {
      _lastAdapterState = isOn;
      if (!firstAdapterState.isCompleted) {
        firstAdapterState.complete(isOn);
      }
      if (!isOn) {
        unawaited(invalidateRuntime());
      }
    });

    final isOn = await firstAdapterState.future;
    _bleBloc.add(BluetoothStateChanged(isOn));
  }

  Future<void> onBackground() => invalidateRuntime();

  Future<void> onForeground() async {
    final isOn = _lastAdapterState ?? await _bleRepository.bluetoothState.first;
    _bleBloc.add(BluetoothStateChanged(isOn));
  }

  Future<void> invalidateRuntime() async {
    if (_cleanupInProgress) return;
    _cleanupInProgress = true;

    try {
      _bleBloc.add(const BluetoothStateChanged(false));
      _connectionBloc.add(const ResetActiveConnections());

      // Ambos servicios son idempotentes; se ejecutan aquí además del BLoC
      // para que la política global no dependa de un único evento GATT.
      await _activeGraphExchange.clear();
      await _clearAllRemoteSnapshots();
    } finally {
      _cleanupInProgress = false;
    }
  }

  Future<void> _clearAllRemoteSnapshots() {
    if (_remoteRelationRepository is RemoteRelationLifecycle) {
      return (_remoteRelationRepository as RemoteRelationLifecycle)
          .clearAllSnapshots();
    }
    return Future<void>.value();
  }

  Future<void> dispose() async {
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    await invalidateRuntime();

    if (_bleRepository is BleRuntimeLifecycle) {
      await (_bleRepository as BleRuntimeLifecycle).disposeRuntime();
    }
    await _liveGraphSync?.dispose();
  }
}

/// Conecta el lifecycle Flutter con [BleLifecycleCoordinator] sin cargar esa
/// política en HomePage.
class BleLifecycleHost extends StatefulWidget {
  final BleLifecycleCoordinator coordinator;
  final Widget child;

  const BleLifecycleHost({
    super.key,
    required this.coordinator,
    required this.child,
  });

  @override
  State<BleLifecycleHost> createState() => _BleLifecycleHostState();
}

class _BleLifecycleHostState extends State<BleLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.coordinator.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(widget.coordinator.onForeground());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(widget.coordinator.onBackground());
      case AppLifecycleState.hidden:
        unawaited(widget.coordinator.onBackground());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
