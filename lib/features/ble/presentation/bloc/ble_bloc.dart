import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend_mobile_nodos_app/core/config/app_config.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/ble_device.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/repositories/ble_repository.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_event.dart';
import 'package:frontend_mobile_nodos_app/features/ble/presentation/bloc/ble_state.dart';

class BleBloc extends Bloc<BleEvent, BleState> {
  final BleRepository repository;
  StreamSubscription<List<BleDevice>>? _scanSubscription;
  StreamSubscription<bool>? _btSubscription;

  /// Período entre reinicios del escaneo para duty cycling.
  ///
  /// Valor por defecto: [dutyCycleScanDuration] + [dutyCyclePauseDuration]
  /// de app_config. En tests se puede inyectar un período más corto.
  final Duration _dutyCyclePeriod;

  /// Acumulador de dispositivos detectados durante el escaneo.
  ///
  /// Clave: [BleDevice.deviceId] (dirección MAC o remoteId).
  /// Valor: [BleDevice] más reciente visto para ese ID.
  ///
  /// QUÉ resuelve: antes cada batch de scanResults reemplazaba el estado
  /// completo, perdiendo dispositivos de batches anteriores (bug B1).
  /// Ahora se acumulan — un dispositivo aparece si fue visto en
  /// CUALQUIER ciclo de escaneo en los últimos 30s.
  final Map<String, BleDevice> _accumulatedDevices = {};

  /// Timer periódico para evicción de dispositivos stale.
  ///
  /// Cada 30 segundos dispara [EvictStaleDevices] que limpia del
  /// [_accumulatedDevices] cualquier dispositivo con timestamp mayor
  /// a 30s de antigüedad. Esto garantiza limpieza incluso cuando
  /// el escaneo BLE no produce nuevos resultados.
  Timer? _evictionTimer;

  /// Timer para duty cycling de escaneo BLE.
  ///
  /// QUÉ hace: reinicia periódicamente el escaneo BLE para evitar
  /// que se detenga permanentemente tras el hard timeout de ~15s
  /// de FlutterBluePlus. Usa [_dutyCyclePeriod] como intervalo.
  ///
  /// POR QUÉ: sin este timer, el escaneo se detiene a los 15s y
  /// nunca se reinicia — el usuario deja de ver dispositivos nuevos.
  /// Con duty cycling, el escaneo es continuo y transparente.
  Timer? _dutyCycleTimer;

  /// Duración máxima desde el último avistamiento antes de evicción.
  static const _staleThreshold = Duration(seconds: 30);

  /// Cantidad máxima de dispositivos acumulados en el mapa.
  static const _maxDevices = 50;

  BleBloc({
    required this.repository,
    Duration? dutyCyclePeriod,
  })  : _dutyCyclePeriod =
            dutyCyclePeriod ?? dutyCycleScanDuration + dutyCyclePauseDuration,
        super(const BleInitial()) {
    on<StartScan>(_onStartScan);
    on<StopScan>(_onStopScan);
    on<StartAdvertise>(_onStartAdvertise);
    on<StopAdvertise>(_onStopAdvertise);
    on<BluetoothStateChanged>(_onBluetoothStateChanged);
    on<_ScanResultsUpdated>(_onScanResultsUpdated);
    on<_ScanError>(_onScanError);
    on<EvictStaleDevices>(_onEvictStaleDevices);

    /// Timer de evicción periódica: cada 30s limpia dispositivos
    /// que no se han visto recientemente.
    ///
    /// QUÉ hace: dispara [EvictStaleDevices] que recorre
    /// [_accumulatedDevices] y elimina entradas con timestamp >30s.
    ///
    /// POR QUÉ: sin este timer, si el escaneo se detiene (sin nuevos
    /// datos BLE) los dispositivos acumulados NUNCA se evictarían.
    /// Con 30s de intervalo, la UI se mantiene actualizada incluso
    /// en períodos sin actividad BLE.
    _evictionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!isClosed) {
          add(const EvictStaleDevices());
        }
      },
    );

    /// Suscripción al estado real del adaptador Bluetooth.
    ///
    /// QUÉ hace: escucha [repository.bluetoothState] y despacha
    /// [BluetoothStateChanged] por cada cambio. El handler
    /// [_onBluetoothStateChanged] mapea true→BleStopped, false→BluetoothOff.
    ///
    /// POR QUÉ resuelve el problema: antes _btSubscription se declaraba
    /// pero NUNCA se asignaba, así que el stream de estado BT era
    /// completamente ignorado y BluetoothOff era inalcanzable.
    _btSubscription = repository.bluetoothState.listen((isOn) {
      if (!isClosed) {
        add(BluetoothStateChanged(isOn));
      }
    });
  }

  Future<void> _onStartScan(StartScan event, Emitter<BleState> emit) async {
    // Cancelar duty cycling anterior si existe (por si se llama StartScan
    // mientras ya hay un ciclo activo).
    _dutyCycleTimer?.cancel();

    try {
      await _scanSubscription?.cancel();
      // Limpiar el acumulador al iniciar un nuevo escaneo.
      // Esto evita que dispositivos de sesiones anteriores persistan
      // en la UI después de un stop/start manual.
      _accumulatedDevices.clear();
      _scanSubscription = repository.scanResults.listen(
        (devices) {
          if (!isClosed) {
            add(_ScanResultsUpdated(devices));
          }
        },
        onError: (error) {
          if (!isClosed) {
            add(_ScanError(error.toString()));
          }
        },
      );
      await repository.startScan();
      emit(const BleScanning());

      // PR6a: Iniciar duty cycling — reinicia el escaneo periódicamente
      // para evitar que el hard timeout de ~15s de FlutterBluePlus
      // detenga el escaneo permanentemente.
      _dutyCycleTimer = Timer.periodic(_dutyCyclePeriod, (_) {
        if (!isClosed) {
          // startScan es idempotente en el datasource (guarda _isScanning).
          // Si el escaneo sigue activo, esta llamada es no-op.
          // Si FlutterBluePlus ya lo detuvo, lo reinicia.
          repository.startScan();
        }
      });
    } catch (e) {
      emit(BleError(e.toString()));
    }
  }

  Future<void> _onStopScan(StopScan event, Emitter<BleState> emit) async {
    // PR6a: Cancelar duty cycling al detener el escaneo manualmente.
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;

    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await repository.stopScan();

    // PR6a: Cerrar la sesión de escaneo con endedAt.
    // Esto completa el ciclo de vida de la sesión.
    await repository.endScanSession();

    emit(const BleStopped());
  }

  Future<void> _onStartAdvertise(
      StartAdvertise event, Emitter<BleState> emit) async {
    await repository.startAdvertise(
      event.deviceUuid,
      event.name,
      event.color,
    );
    emit(const BleAdvertising());
  }

  Future<void> _onStopAdvertise(
      StopAdvertise event, Emitter<BleState> emit) async {
    await repository.stopAdvertise();
    emit(const BleStopped());
  }

  void _onBluetoothStateChanged(
      BluetoothStateChanged event, Emitter<BleState> emit) {
    if (event.isOn) {
      emit(const BleStopped());
    } else {
      emit(const BluetoothOff());
    }
  }

  /// Fusión, evicción y capping de dispositivos BLE (función pura).
  ///
  /// QUÉ hace: recibe un mapa acumulado y un batch entrante de dispositivos.
  /// 1. Fusiona: inserta/actualiza cada dispositivo del batch en el mapa
  ///    usando deviceId como clave.
  /// 2. Evicción: elimina entradas cuyo timestamp tenga más de [staleThreshold]
  ///    de antigüedad respecto a DateTime.now().
  /// 3. Capping: si el mapa supera [maxDevices], ordena por timestamp
  ///    descendente y trunca a los [maxDevices] más recientes.
  ///
  /// Retorna la lista resultante. Es pura: no modifica el mapa original,
  /// opera sobre una copia. Sin side effects — ideal para testing unitario.
  ///
  /// POR QUÉ es estática y pública: permite testear la lógica de acumulación
  /// sin depender de BLoC, streams, o timers. Extract-Before-Mock pattern.
  @visibleForTesting
  static List<BleDevice> accumulateDevices(
    Map<String, BleDevice> current,
    List<BleDevice> incoming, {
    Duration staleThreshold = _staleThreshold,
    int maxDevices = _maxDevices,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final merged = Map<String, BleDevice>.from(current);

    // Paso 1: Fusionar
    for (final device in incoming) {
      final existing = merged[device.deviceId];
      if (existing == null || device.timestamp.isAfter(existing.timestamp)) {
        merged[device.deviceId] = device;
      }
    }

    // Paso 2: Evicción por antigüedad
    merged.removeWhere((_, device) {
      final age = effectiveNow.difference(device.timestamp);
      return age > staleThreshold;
    });

    // Paso 3: Capping
    if (merged.length > maxDevices) {
      final sorted = merged.entries.toList()
        ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
      return sorted.take(maxDevices).map((e) => e.value).toList();
    }

    return merged.values.toList();
  }

  /// Fusiona dispositivos del batch actual en el acumulador, aplica
  /// evicción por antigüedad, capping a 50 y emite la lista acumulada.
  ///
  /// Delega la lógica pesada a [accumulateDevices] (función pura) y
  /// actualiza [_accumulatedDevices] + emite el resultado.
  void _onScanResultsUpdated(
      _ScanResultsUpdated event, Emitter<BleState> emit) {
    final accumulated = accumulateDevices(
      _accumulatedDevices,
      event.devices,
    );

    // Reconstruir el mapa desde la lista resultante
    _accumulatedDevices.clear();
    for (final device in accumulated) {
      _accumulatedDevices[device.deviceId] = device;
    }
    emit(BleScanning(devices: accumulated));
  }

  /// Limpia dispositivos stale del acumulador sin nuevos datos BLE.
  ///
  /// Disparado por el timer periódico cada 30s. Si después de la evicción
  /// la lista cambió (se removió al menos un dispositivo), emite el
  /// nuevo estado para que la UI se actualice.
  void _onEvictStaleDevices(
      EvictStaleDevices event, Emitter<BleState> emit) {
    if (_accumulatedDevices.isEmpty) return;

    final before = _accumulatedDevices.length;
    final now = DateTime.now();

    _accumulatedDevices.removeWhere((_, device) {
      final age = now.difference(device.timestamp);
      return age > _staleThreshold;
    });

    if (_accumulatedDevices.length < before) {
      emit(BleScanning(devices: _accumulatedDevices.values.toList()));
    }
  }

  void _onScanError(_ScanError event, Emitter<BleState> emit) {
    emit(BleError(event.message));
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    _btSubscription?.cancel();
    _evictionTimer?.cancel();
    _evictionTimer = null;
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
    return super.close();
  }
}

/// Internal event for scan result updates.
class _ScanResultsUpdated extends BleEvent {
  final List<BleDevice> devices;

  const _ScanResultsUpdated(this.devices);

  @override
  List<Object> get props => [devices];
}

/// Internal event for scan stream errors.
class _ScanError extends BleEvent {
  final String message;

  const _ScanError(this.message);

  @override
  List<Object> get props => [message];
}
