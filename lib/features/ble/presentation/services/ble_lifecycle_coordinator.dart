import 'dart:async';

import 'package:flutter/material.dart';

import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/remote_relation_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_connection_bloc.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/services/live_graph_sync_service.dart';

/// Centraliza la invalidación del runtime BLE.
///
/// `connections` no participa de este cleanup: representa LINKED persistente.
/// En cambio, el scan, las conexiones GATT, el grafo activo y
/// `remote_relations` representan estado de la ejecución actual.
class BleLifecycleCoordinator {
  final BleRepository _bleRepository;
  final RemoteRelationRepository _remoteRelationRepository;
  final BleBloc _bleBloc;
  final BleConnectionBloc _connectionBloc;
  final LiveGraphSyncService? _liveGraphSync;

  StreamSubscription<bool>? _adapterSubscription;
  Future<void>? _cleanupFuture;
  bool? _lastAdapterState;
  bool _runtimeInvalidated = false;

  BleLifecycleCoordinator({
    required BleRepository bleRepository,
    required RemoteRelationRepository remoteRelationRepository,
    required BleBloc bleBloc,
    required BleConnectionBloc connectionBloc,
    LiveGraphSyncService? liveGraphSync,
  }) : _bleRepository = bleRepository,
       _remoteRelationRepository = remoteRelationRepository,
       _bleBloc = bleBloc,
       _connectionBloc = connectionBloc,
       _liveGraphSync = liveGraphSync;

  Future<void> initialize() async {
    _runtimeInvalidated = false;
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
        unawaited(invalidateRuntime(bluetoothOn: false));
      }
    });

    final isOn = await firstAdapterState.future;
    if (!isOn) {
      await invalidateRuntime(bluetoothOn: false);
    }
  }

  /// `inactive` is intentionally not routed here: on iOS it is commonly a
  /// transient transition (Control Center, calls, permission dialogs).
  void onInactive() {}

  Future<void> onBackground() => invalidateRuntime(bluetoothOn: true);

  Future<void> onDetached() => invalidateRuntime(bluetoothOn: true);

  Future<void> onForeground() async {
    final isOn = _lastAdapterState ?? await _bleRepository.bluetoothState.first;
    _runtimeInvalidated = false;
    if (!isOn) {
      await invalidateRuntime(bluetoothOn: false);
    }
    // Resume only reconciles the adapter. It deliberately does not scan,
    // advertise, reconnect, or restore a Graph Exchange session.
  }

  Future<void> invalidateRuntime({bool bluetoothOn = true}) {
    if (_runtimeInvalidated) return Future<void>.value();
    final inFlight = _cleanupFuture;
    if (inFlight != null) return inFlight;

    final operation = _performRuntimeInvalidation(bluetoothOn: bluetoothOn);
    _cleanupFuture = operation;
    return operation.whenComplete(() {
      if (identical(_cleanupFuture, operation)) {
        _cleanupFuture = null;
        _runtimeInvalidated = true;
      }
    });
  }

  Future<void> _performRuntimeInvalidation({required bool bluetoothOn}) async {
    try {
      await _liveGraphSync?.pause();
      await _bleBloc.invalidateRuntime(bluetoothOn: bluetoothOn);
      await _connectionBloc.invalidateRuntime();
    } catch (_) {
      // A lifecycle transition must remain best-effort at the platform
      // boundary; the next transition can retry the cleanup.
      rethrow;
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
    await invalidateRuntime(bluetoothOn: true);

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
        widget.coordinator.onInactive();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(widget.coordinator.onBackground());
      case AppLifecycleState.detached:
        unawaited(widget.coordinator.onDetached());
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
