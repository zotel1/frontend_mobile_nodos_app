/// Pure BLE capacity policy shared by central and peripheral transports.
///
/// An ATT MTU is not the same value as the ATT payload capacity, and neither
/// is the payload capacity available to the Nodos framing envelope.
class BleMtuPolicy {
  static const int fallbackMtu = 23;
  static const int minimumMtu = fallbackMtu;
  static const int attOverhead = 3;
  static const int maxFragmentPayload = 255;

  final int effectiveMtu;

  const BleMtuPolicy._(this.effectiveMtu);

  /// Builds a policy from a platform snapshot, using 23 only when it is not
  /// a valid ATT MTU. The fallback is compatibility behavior, not a platform
  /// assumption.
  factory BleMtuPolicy.fromMtu(int? mtu) {
    final effective = mtu != null && mtu >= minimumMtu ? mtu : fallbackMtu;
    return BleMtuPolicy._(effective);
  }

  int get attPayloadCapacity => effectiveMtu - attOverhead;

  int get framedPayloadCapacity {
    final calculated = attPayloadCapacity - BleMtuPolicy.frameHeaderLength;
    return calculated.clamp(1, maxFragmentPayload);
  }

  /// The 18-byte envelope is owned by the transport codec, not duplicated in
  /// each platform adapter.
  static const int frameHeaderLength = 18;

  static int centralWriteCapacity(int? mtu) =>
      BleMtuPolicy.fromMtu(mtu).framedPayloadCapacity;

  /// [maximumUpdateValueLength] is intentionally optional: flutter_ble_peripheral
  /// 3.1.0 does not expose the subscribed central's negotiated capacity in its
  /// Dart API, so the safe fallback remains the framed capacity for MTU 23.
  static int peripheralNotificationCapacity({int? maximumUpdateValueLength}) {
    if (maximumUpdateValueLength == null || maximumUpdateValueLength <= 0) {
      return centralWriteCapacity(null);
    }
    return maximumUpdateValueLength.clamp(1, maxFragmentPayload);
  }
}
