import 'dart:async';
import 'dart:typed_data';

import 'ble_frame.dart';
import 'ble_frame_codec.dart';

typedef BleNow = DateTime Function();

/// Reassembles independently interleaved BLE messages with bounded memory.
class BleMessageReassembler {
  final Duration timeout;
  final BleNow _now;
  final Map<int, _PartialMessage> _messages = <int, _PartialMessage>{};
  Timer? _cleanupTimer;

  BleMessageReassembler({
    this.timeout = const Duration(seconds: 10),
    BleNow? now,
    bool scheduleCleanup = true,
  }) : _now = now ?? DateTime.now {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (scheduleCleanup) {
      _cleanupTimer = Timer.periodic(timeout, (_) => expire());
    }
  }

  int get inProgressCount => _messages.length;

  /// Adds one framed fragment. Returns a complete message only at completion.
  Uint8List? add(List<int> bytes) {
    // Compatibility for pre-FEAT-004F peers: non-framed data is accepted as
    // one complete legacy message. Framed data always goes through reassembly.
    if (!BleFrameCodec.hasMagic(bytes)) {
      return Uint8List.fromList(bytes);
    }

    final frame = BleFrameCodec.decode(bytes);
    if (frame.totalFragments > BleTransportLimits.maxFragments ||
        frame.totalPayloadLength > BleTransportLimits.maxMessageSize) {
      throw const FormatException('BLE message exceeds configured limits');
    }

    var message = _messages[frame.messageId];
    if (message == null) {
      if (_messages.length >= BleTransportLimits.maxConcurrentMessages) {
        throw const FormatException('Too many incomplete BLE messages');
      }
      message = _PartialMessage.fromFrame(frame, _now());
      _messages[frame.messageId] = message;
    } else if (!message.matches(frame)) {
      _messages.remove(frame.messageId);
      throw const FormatException('Conflicting BLE fragment metadata');
    }

    final existing = message.fragments[frame.sequenceIndex];
    if (existing != null) {
      if (!_sameBytes(existing, frame.payload)) {
        _messages.remove(frame.messageId);
        throw const FormatException('Conflicting duplicate BLE fragment');
      }
      return null;
    }

    message.fragments[frame.sequenceIndex] = frame.payload;
    if (message.fragments.length != frame.totalFragments) return null;

    final complete = BytesBuilder(copy: false);
    for (var index = 0; index < frame.totalFragments; index++) {
      final fragment = message.fragments[index];
      if (fragment == null) return null;
      complete.add(fragment);
    }

    final bytesResult = Uint8List.fromList(complete.takeBytes());
    _messages.remove(frame.messageId);
    if (bytesResult.length != frame.totalPayloadLength ||
        BleFrameCodec.checksum(bytesResult) != frame.checksum) {
      throw const FormatException('BLE message checksum or length mismatch');
    }
    return bytesResult;
  }

  /// Removes messages older than [timeout]. Returns the number removed.
  int expire([DateTime? now]) {
    final cutoff = (now ?? _now()).subtract(timeout);
    final expired = _messages.keys
        .where((id) => _messages[id]!.createdAt.isBefore(cutoff))
        .toList();
    for (final id in expired) {
      _messages.remove(id);
    }
    return expired.length;
  }

  void clear() => _messages.clear();

  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    clear();
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

class _PartialMessage {
  final int totalFragments;
  final int totalPayloadLength;
  final int checksum;
  final DateTime createdAt;
  final Map<int, Uint8List> fragments = <int, Uint8List>{};

  _PartialMessage({
    required this.totalFragments,
    required this.totalPayloadLength,
    required this.checksum,
    required this.createdAt,
  });

  factory _PartialMessage.fromFrame(BleFrame frame, DateTime now) {
    return _PartialMessage(
      totalFragments: frame.totalFragments,
      totalPayloadLength: frame.totalPayloadLength,
      checksum: frame.checksum,
      createdAt: now,
    );
  }

  bool matches(BleFrame frame) {
    return totalFragments == frame.totalFragments &&
        totalPayloadLength == frame.totalPayloadLength &&
        checksum == frame.checksum;
  }
}
