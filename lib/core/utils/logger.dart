import 'dart:developer' as developer;

/// Simple logger wrapper around `dart:developer` log().
///
/// Prefixes all messages with '[Nodos]' for easy filtering.
class Logger {
  final String _tag;

  Logger(this._tag);

  void debug(String message) {
    developer.log(message, name: _tag, level: 500);
  }

  void info(String message) {
    developer.log(message, name: _tag, level: 800);
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
