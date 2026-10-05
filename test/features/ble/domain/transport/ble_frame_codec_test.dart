import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/entities/nodos_graph_payload.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_frame_codec.dart';
import 'package:frontend_mobile_nodos_app/features/ble/domain/transport/ble_message_reassembler.dart';

void main() {
  test('small payload uses one frame and round trips exactly', () {
    final payload = Uint8List.fromList(List<int>.generate(10, (i) => i));
    final frames = BleMessageFramer(
      initialMessageId: 7,
    ).frame(payload, mtu: 64);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    expect(frames, hasLength(1));
    expect(reassembler.add(frames.single), payload);
  });

  test('large payload is fragmented and reassembled', () {
    final payload = Uint8List.fromList(
      List<int>.generate(4096, (i) => i % 251),
    );
    final frames = BleMessageFramer(
      initialMessageId: 8,
    ).frame(payload, mtu: 64);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    Uint8List? result;
    for (final frame in frames) {
      result = reassembler.add(frame);
    }

    expect(frames.length, greaterThan(1));
    expect(result, payload);
  });

  test('out of order fragments are reassembled', () {
    final payload = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final frames = BleMessageFramer(
      initialMessageId: 9,
    ).frame(payload, mtu: 40);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    Uint8List? result;
    for (final index in <int>[2, 0, 1]) {
      result = reassembler.add(frames[index]);
    }

    expect(result, payload);
  });

  test('duplicate fragment does not duplicate bytes', () {
    final payload = Uint8List.fromList(List<int>.generate(100, (i) => i));
    final frames = BleMessageFramer(
      initialMessageId: 10,
    ).frame(payload, mtu: 40);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    reassembler.add(frames[0]);
    expect(reassembler.add(frames[0]), isNull);
    for (final frame in frames.skip(1)) {
      reassembler.add(frame);
    }
    expect(reassembler.inProgressCount, 0);
  });

  test('missing fragment remains incomplete', () {
    final frames = BleMessageFramer(
      initialMessageId: 11,
    ).frame(Uint8List.fromList(List<int>.generate(100, (i) => i)), mtu: 40);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    expect(reassembler.add(frames[0]), isNull);
    expect(reassembler.add(frames[2]), isNull);
    expect(reassembler.inProgressCount, 1);
  });

  test('timeout removes incomplete messages', () {
    var now = DateTime(2026, 1, 1);
    final frames = BleMessageFramer(
      initialMessageId: 12,
    ).frame(Uint8List.fromList(List<int>.generate(100, (i) => i)), mtu: 40);
    final reassembler = BleMessageReassembler(
      timeout: const Duration(seconds: 5),
      now: () => now,
      scheduleCleanup: false,
    );

    reassembler.add(frames.first);
    now = now.add(const Duration(seconds: 6));
    expect(reassembler.expire(), 1);
    expect(reassembler.inProgressCount, 0);
  });

  test('checksum corruption is rejected', () {
    final frame = BleMessageFramer(initialMessageId: 13)
        .frame(Uint8List.fromList(List<int>.generate(20, (i) => i)), mtu: 64)
        .single;
    frame[frame.length - 1] ^= 0xff;
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    expect(() => reassembler.add(frame), throwsFormatException);
    expect(reassembler.inProgressCount, 0);
  });

  test('invalid headers are rejected safely', () {
    final reassembler = BleMessageReassembler(scheduleCleanup: false);
    final valid = BleMessageFramer(
      initialMessageId: 14,
    ).frame([1, 2, 3], mtu: 64).single;
    final invalid = Uint8List.fromList(valid);
    invalid[7] = 0xff;
    invalid[8] = 0xff;

    expect(() => BleFrameCodec.decode(invalid), throwsFormatException);
    expect(() => reassembler.add(Uint8List(18)), returnsNormally);
  });

  test('message and fragment limits are enforced', () {
    expect(
      () => BleMessageFramer().frame(
        List<int>.filled(BleTransportLimits.maxMessageSize + 1, 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => BleTransportLimits.chunkPayloadSizeForMtu(22),
      throwsArgumentError,
    );
  });

  test('multiple interleaved message ids reassemble independently', () {
    final framer = BleMessageFramer(initialMessageId: 20);
    final first = framer.frame(List<int>.generate(20, (i) => i), mtu: 30);
    final second = framer.frame(List<int>.generate(20, (i) => i + 20), mtu: 30);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);

    expect(reassembler.add(first[0]), isNull);
    expect(reassembler.add(second[0]), isNull);
    expect(reassembler.add(first[1]), isNull);
    expect(reassembler.add(second[1]), isNull);
    expect(reassembler.add(first[2]), List<int>.generate(20, (i) => i));
    expect(reassembler.add(second[2]), List<int>.generate(20, (i) => i + 20));
  });

  test('graph snapshot bytes round trip through framing', () {
    final payload = NodosGraphPayload(
      ownerUuid: 'owner',
      connections: List.generate(
        30,
        (index) => NodosGraphConnection.nodos(
          deviceUuid: 'peer-$index',
          name: 'Node $index',
          color: '#abcdef',
        ),
      ),
    );
    final frames = BleMessageFramer(
      initialMessageId: 30,
    ).frame(payload.toBytes(), mtu: 64);
    final reassembler = BleMessageReassembler(scheduleCleanup: false);
    Uint8List? bytes;
    for (final frame in frames.reversed) {
      bytes = reassembler.add(frame);
    }

    expect(NodosGraphPayload.fromBytes(bytes!), payload);
  });
}
