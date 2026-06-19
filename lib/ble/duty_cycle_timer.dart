import 'dart:async';

/// States of the duty cycle timer state machine.
enum DutyCycleState { idle, scanning, paused }

/// Signature for one-shot timer creation.
typedef TimerFactory = void Function() Function(
    Duration duration, void Function() callback);

/// Signature for periodic timer creation.
typedef PeriodicFactory = void Function() Function(
    Duration period, void Function() callback);

/// A duty-cycle timer that alternates between SCANNING and PAUSED states.
///
/// Each cycle: calls [onScanTick] → waits [scanDuration] → calls [onPauseTick]
/// → waits [pauseDuration] → the periodic timer triggers the next cycle.
///
/// The first cycle begins immediately when [start] is called.
class DutyCycleTimer {
  final Duration scanDuration;
  final Duration pauseDuration;

  final TimerFactory _createTimer;
  final PeriodicFactory _createPeriodic;

  DutyCycleState _state = DutyCycleState.idle;
  bool _running = false;
  void Function()? _cancelPeriodic;
  void Function()? _cancelScan;

  DutyCycleTimer._({
    required this.scanDuration,
    required this.pauseDuration,
    required this._createTimer,
    required this._createPeriodic,
  });

  /// Creates a [DutyCycleTimer] that uses real [Timer]-based scheduling.
  factory DutyCycleTimer({
    required Duration scanDuration,
    required Duration pauseDuration,
  }) {
    return DutyCycleTimer._(
      scanDuration: scanDuration,
      pauseDuration: pauseDuration,
      createTimer: _realTimer,
      createPeriodic: _realPeriodic,
    );
  }

  /// Creates a [DutyCycleTimer] with injected timer factories (for testing).
  factory DutyCycleTimer.withTimerFactories({
    required Duration scanDuration,
    required Duration pauseDuration,
    required TimerFactory createTimer,
    required PeriodicFactory createPeriodic,
  }) {
    return DutyCycleTimer._(
      scanDuration: scanDuration,
      pauseDuration: pauseDuration,
      createTimer: createTimer,
      createPeriodic: createPeriodic,
    );
  }

  static void Function() _realTimer(Duration d, void Function() cb) {
    final t = Timer(d, cb);
    return () => t.cancel();
  }

  static void Function() _realPeriodic(Duration d, void Function() cb) {
    final t = Timer.periodic(d, (_) => cb());
    return () => t.cancel();
  }

  /// Whether the duty cycle is currently running.
  bool get isRunning => _running;

  /// Current state of the state machine.
  DutyCycleState get state => _state;

  /// Starts the duty cycle.
  ///
  /// If already running, this call is ignored (no double-start).
  ///
  /// Each cycle:
  ///   1. Sets state to [DutyCycleState.scanning] and calls [onScanTick].
  ///   2. After [scanDuration], sets state to [DutyCycleState.paused] and
  ///      calls [onPauseTick].
  ///   3. After [pauseDuration], the periodic timer triggers the next cycle.
  void start({
    required void Function() onScanTick,
    required void Function() onPauseTick,
  }) {
    if (_running) return;
    _running = true;

    void runCycle() {
      _state = DutyCycleState.scanning;
      onScanTick();

      _cancelScan = _createTimer(scanDuration, () {
        _state = DutyCycleState.paused;
        onPauseTick();
      });
    }

    // First cycle fires immediately.
    runCycle();

    // Subsequent cycles fire every (scanDuration + pauseDuration).
    _cancelPeriodic = _createPeriodic(scanDuration + pauseDuration, runCycle);
  }

  /// Stops the duty cycle, cancelling all timers and resetting to IDLE.
  ///
  /// Safe to call from any state, including already-IDLE.
  void stop() {
    _cancelPeriodic?.call();
    _cancelScan?.call();
    _cancelPeriodic = null;
    _cancelScan = null;
    _running = false;
    _state = DutyCycleState.idle;
  }
}
