import 'dart:typed_data';

/// Version of the transport envelope. This is independent from payload
/// protocol versions such as [NodosGraphPayload.currentVersion].
const int bleTransportFrameVersion = 1;

/// Compact binary envelope for one fragment of a BLE message.
class BleFrame {
  final int messageId;
  final int sequenceIndex;
  final int totalFragments;
  final int totalPayloadLength;
  final int checksum;
  final Uint8List payload;

  const BleFrame({
    required this.messageId,
    required this.sequenceIndex,
    required this.totalFragments,
    required this.totalPayloadLength,
    required this.checksum,
    required this.payload,
  });
}
