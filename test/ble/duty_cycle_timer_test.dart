import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/ble/duty_cycle_timer.dart';

/// A controllable timer that captures the callback and provides explicit
/// [fire] and cancel support.
class _ControllableTimer {
  final void Function() _callback;
  bool cancelled = false;

  _ControllableTimer(Duration duration, this._callback);

  void fire() {
    if (!cancelled) _callback();
  }

  void Function() toCancelFn() => () => cancelled = true;
}

/// A controllable periodic timer.
class _ControllablePeriodic {
  final void Function() _callback;
  bool cancelled = false;

  _ControllablePeriodic(Duration period, this._callback);

  void fire() {
    if (!cancelled) _callback();
  }

  void Function() toCancelFn() => () => cancelled = true;
}

/// Creates a [DutyCycleTimer] wired with controllable timers for testing.
///
/// Returns the timer and captured timer objects so tests can fire callbacks
/// to simulate time and verify cancellation.
({DutyCycleTimer timer, List<_ControllableTimer> scanTimers, List<_ControllablePeriodic> periodicTimers})
    createTestTimer() {
  final scanTimers = <_ControllableTimer>[];
  final periodicTimers = <_ControllablePeriodic>[];

  final timer = DutyCycleTimer.withTimerFactories(
    scanDuration: const Duration(seconds: 2),
    pauseDuration: const Duration(seconds: 8),
    createTimer: (d, cb) {
      final ct = _ControllableTimer(d, cb);
      scanTimers.add(ct);
      return ct.toCancelFn();
    },
    createPeriodic: (d, cb) {
      final cp = _ControllablePeriodic(d, cb);
      periodicTimers.add(cp);
      return cp.toCancelFn();
    },
  );

  return (timer: timer, scanTimers: scanTimers, periodicTimers: periodicTimers);
}

void main() {
  group('DutyCycleTimer — DCYC-001', () {
    test('start() → state becomes scanning and onScanTick is called immediately',
        () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      var scanTicked = false;
      var pauseTicked = false;

      timer.start(
        onScanTick: () => scanTicked = true,
        onPauseTick: () => pauseTicked = true,
      );

      expect(timer.state, DutyCycleState.scanning);
      expect(timer.isRunning, isTrue);
      expect(scanTicked, isTrue);
      expect(pauseTicked, isFalse);
    });

    test(
        'after scan duration → state becomes paused and onPauseTick is called',
        () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      var pauseTicked = false;

      timer.start(
        onScanTick: () {},
        onPauseTick: () => pauseTicked = true,
      );

      expect(scanTimers, isNotEmpty);
      scanTimers.first.fire();

      expect(timer.state, DutyCycleState.paused);
      expect(pauseTicked, isTrue);
    });

    test(
        'periodic tick fires → state cycles back to scanning and onScanTick called again',
        () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      var scanCount = 0;
      timer.start(
        onScanTick: () => scanCount++,
        onPauseTick: () {},
      );

      expect(scanCount, 1);
      expect(timer.state, DutyCycleState.scanning);

      scanTimers.first.fire();
      expect(timer.state, DutyCycleState.paused);

      expect(periodicTimers, isNotEmpty);
      periodicTimers.first.fire();
      expect(timer.state, DutyCycleState.scanning);
      expect(scanCount, 2);
    });

    test('stop() while SCANNING → state becomes IDLE', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      timer.start(onScanTick: () {}, onPauseTick: () {});
      expect(timer.state, DutyCycleState.scanning);

      timer.stop();

      expect(timer.state, DutyCycleState.idle);
      expect(timer.isRunning, isFalse);
    });

    test('stop() while PAUSED → state becomes IDLE', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      timer.start(onScanTick: () {}, onPauseTick: () {});
      scanTimers.first.fire();
      expect(timer.state, DutyCycleState.paused);

      timer.stop();

      expect(timer.state, DutyCycleState.idle);
      expect(timer.isRunning, isFalse);
    });

    test('stop() cancels timers — no more callbacks after stop', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      var pauseTicked = false;
      timer.start(
        onScanTick: () {},
        onPauseTick: () => pauseTicked = true,
      );

      timer.stop();

      // Timers should be marked cancelled
      expect(scanTimers.first.cancelled, isTrue);
      expect(periodicTimers.first.cancelled, isTrue);

      // onPauseTick should never have been called
      expect(pauseTicked, isFalse);
    });

    test('rapid toggle start/stop 5x → final state IDLE, no crash', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      for (var i = 0; i < 5; i++) {
        timer.start(onScanTick: () {}, onPauseTick: () {});
        timer.stop();
      }

      expect(timer.state, DutyCycleState.idle);
      expect(timer.isRunning, isFalse);
    });

    test('double start → ignored, only one running', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      var scanCount = 0;
      timer.start(
        onScanTick: () => scanCount++,
        onPauseTick: () {},
      );
      expect(scanCount, 1);
      expect(timer.isRunning, isTrue);

      timer.start(
        onScanTick: () => scanCount++,
        onPauseTick: () {},
      );
      expect(scanCount, 1);
      expect(timer.isRunning, isTrue);
    });

    test('isRunning is false before start()', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      expect(timer.isRunning, isFalse);
      expect(timer.state, DutyCycleState.idle);
    });

    test('stop() on already-IDLE timer does nothing', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      expect(timer.state, DutyCycleState.idle);
      timer.stop();
      expect(timer.state, DutyCycleState.idle);
      expect(timer.isRunning, isFalse);
    });

    test('full cycle: scanning → paused → scanning → stopped → idle', () {
      final (:timer, :scanTimers, :periodicTimers) = createTestTimer();

      var scanCount = 0;
      var pauseCount = 0;
      timer.start(
        onScanTick: () => scanCount++,
        onPauseTick: () => pauseCount++,
      );

      expect(timer.state, DutyCycleState.scanning);
      expect(scanCount, 1);
      expect(pauseCount, 0);

      scanTimers.first.fire();
      expect(timer.state, DutyCycleState.paused);
      expect(pauseCount, 1);

      periodicTimers.first.fire();
      expect(timer.state, DutyCycleState.scanning);
      expect(scanCount, 2);

      timer.stop();
      expect(timer.state, DutyCycleState.idle);
      expect(timer.isRunning, isFalse);
      expect(scanCount, 2);
    });
  });
}
