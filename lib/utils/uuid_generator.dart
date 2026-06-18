import 'package:uuid/uuid.dart';

/// Generates a random UUID v4 string.
///
/// Uses the [uuid] package to produce RFC 4122 compliant UUIDs
/// in the format: xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx
String generateUuidV4() {
  return const Uuid().v4();
}
