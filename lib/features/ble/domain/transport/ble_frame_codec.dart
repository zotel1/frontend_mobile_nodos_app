import 'dart:typed_data';

import 'ble_frame.dart';

/// Limits and framing rules shared by central and peripheral transports.
class BleTransportLimits {
  static const int frameHeaderLength = 18;
  static const int defaultMtu = 23;
  static const int maxMessageSize = 0xffff;
  static const int maxFragments = 0xffff;
  static const int maxConcurrentMessages = 8;

  static int chunkPayloadSizeForMtu(int mtu) {
    if (mtu < defaultMtu) {
      throw ArgumentError.value(mtu, 'mtu', 'must be at least 23');
    }

    final attPayload = mtu - 3;
    final chunkSize = attPayload - frameHeaderLength;
    if (chunkSize <= 0) {
      throw ArgumentError.value(mtu, 'mtu', 'cannot fit a transport frame');
    }

    return chunkSize > 255 ? 255 : chunkSize;
  }
}

/// Encodes and decodes the versioned binary transport envelope.
class BleFrameCodec {
  static const int _magic0 = 0x4e;
  static const int _magic1 = 0x46;
  static const int _maxUint16 = 0xffff;
  static const int _maxUint32 = 0xffffffff;

  static bool hasMagic(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == _magic0 && bytes[1] == _magic1;
  }

  static Uint8List encode(BleFrame frame) {
    if (frame.messageId < 0 || frame.messageId > _maxUint32) {
      throw ArgumentError.value(frame.messageId, 'messageId');
    }
    if (frame.sequenceIndex < 0 ||
        frame.sequenceIndex >= frame.totalFragments ||
        frame.totalFragments <= 0 ||
        frame.totalFragments > BleTransportLimits.maxFragments) {
      throw ArgumentError('Invalid fragment sequence metadata');
    }
    if (frame.totalPayloadLength <= 0 ||
        frame.totalPayloadLength > BleTransportLimits.maxMessageSize ||
        frame.totalPayloadLength > _maxUint16) {
      throw ArgumentError.value(frame.totalPayloadLength, 'totalPayloadLength');
    }
    if (frame.payload.isEmpty || frame.payload.length > 255) {
      throw ArgumentError.value(frame.payload.length, 'payload');
    }

    final result = Uint8List(
      BleTransportLimits.frameHeaderLength + frame.payload.length,
    );
    final data = ByteData.sublistView(result);
    result[0] = _magic0;
    result[1] = _magic1;
    result[2] = bleTransportFrameVersion;
    data.setUint32(3, frame.messageId, Endian.big);
    data.setUint16(7, frame.sequenceIndex, Endian.big);
    data.setUint16(9, frame.totalFragments, Endian.big);
    data.setUint16(11, frame.totalPayloadLength, Endian.big);
    data.setUint32(13, frame.checksum, Endian.big);
    result[17] = frame.payload.length;
    result.setRange(
      BleTransportLimits.frameHeaderLength,
      result.length,
      frame.payload,
    );
    return result;
  }

  static BleFrame decode(
    List<int> bytes, {
    int maxMessageSize = BleTransportLimits.maxMessageSize,
  }) {
    if (bytes.length < BleTransportLimits.frameHeaderLength ||
        !hasMagic(bytes)) {
      throw const FormatException('Invalid BLE frame header');
    }

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    if (bytes[2] != bleTransportFrameVersion) {
      throw FormatException('Unsupported BLE transport version: ${bytes[2]}');
    }

    final messageId = data.getUint32(3, Endian.big);
    final sequenceIndex = data.getUint16(7, Endian.big);
    final totalFragments = data.getUint16(9, Endian.big);
    final totalPayloadLength = data.getUint16(11, Endian.big);
    final checksum = data.getUint32(13, Endian.big);
    final fragmentLength = bytes[17];

    if (totalFragments == 0 ||
        totalFragments > BleTransportLimits.maxFragments ||
        sequenceIndex >= totalFragments ||
        totalPayloadLength == 0 ||
        totalPayloadLength > maxMessageSize ||
        totalPayloadLength > BleTransportLimits.maxMessageSize ||
        fragmentLength == 0 ||
        bytes.length != BleTransportLimits.frameHeaderLength + fragmentLength) {
      throw const FormatException('Invalid BLE frame metadata');
    }

    return BleFrame(
      messageId: messageId,
      sequenceIndex: sequenceIndex,
      totalFragments: totalFragments,
      totalPayloadLength: totalPayloadLength,
      checksum: checksum,
      payload: Uint8List.fromList(
        bytes.sublist(BleTransportLimits.frameHeaderLength),
      ),
    );
  }

  static int checksum(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte & 0xff;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & _maxUint32;
  }
}

/// Splits one complete payload into ordered transport frames.
class BleMessageFramer {
  int _nextMessageId;

  BleMessageFramer({int? initialMessageId})
    : _nextMessageId = initialMessageId ?? 1;

  List<Uint8List> frame(
    List<int> payload, {
    int mtu = BleTransportLimits.defaultMtu,
  }) {
    if (payload.isEmpty || payload.length > BleTransportLimits.maxMessageSize) {
      throw ArgumentError.value(payload.length, 'payload');
    }

    final chunkSize = BleTransportLimits.chunkPayloadSizeForMtu(mtu);
    final totalFragments = (payload.length + chunkSize - 1) ~/ chunkSize;
    if (totalFragments > BleTransportLimits.maxFragments) {
      throw ArgumentError('Payload requires too many BLE fragments');
    }

    final messageId = _nextMessageId++ & 0xffffffff;
    if (messageId == 0) _nextMessageId = 1;
    final bytes = Uint8List.fromList(payload);
    final checksum = BleFrameCodec.checksum(bytes);
    final frames = <Uint8List>[];

    for (var index = 0; index < totalFragments; index++) {
      final start = index * chunkSize;
      final end = (start + chunkSize).clamp(start, bytes.length);
      frames.add(
        BleFrameCodec.encode(
          BleFrame(
            messageId: messageId,
            sequenceIndex: index,
            totalFragments: totalFragments,
            totalPayloadLength: bytes.length,
            checksum: checksum,
            payload: Uint8List.sublistView(bytes, start, end),
          ),
        ),
      );
    }
    return frames;
  }
}
