import 'package:flutter/foundation.dart';

enum AppLogLevel { info, warn, error }

class AppLogEntry {
  const AppLogEntry({
    required this.level,
    required this.message,
    required this.recordedAt,
    this.error,
    this.stackTrace,
  });

  final AppLogLevel level;
  final String message;
  final DateTime recordedAt;
  final String? error;
  final String? stackTrace;

  String get levelLabel => switch (level) {
    AppLogLevel.info => 'INFO',
    AppLogLevel.warn => 'WARN',
    AppLogLevel.error => 'ERROR',
  };

  String toDiagnosticLine() {
    final buffer = StringBuffer(
      '[${recordedAt.toIso8601String()}] [$levelLabel] $message',
    );
    if (error != null && error!.isNotEmpty) {
      buffer.write(' | $error');
    }
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}

abstract final class AppLog {
  static const _maxEntries = 120;
  static final List<AppLogEntry> _entries = [];

  static void info(String message) {
    _record(AppLogLevel.info, message);
    if (kReleaseMode) {
      // ignore: avoid_print
      print('[INFO] $message');
    } else {
      debugPrint('[INFO] $message');
    }
  }

  static void warn(String message) {
    _record(AppLogLevel.warn, message);
    if (kReleaseMode) {
      // ignore: avoid_print
      print('[WARN] $message');
    } else {
      debugPrint('[WARN] $message');
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _record(AppLogLevel.error, message, error: error, stackTrace: stackTrace);
    final buffer = StringBuffer('[ERROR] $message');
    if (error != null) {
      buffer.write(' | $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    if (kReleaseMode) {
      // ignore: avoid_print
      print(buffer.toString());
    } else {
      debugPrint(buffer.toString());
    }
  }

  static List<AppLogEntry> recentEntries() {
    return List<AppLogEntry>.unmodifiable(_entries.reversed);
  }

  static String diagnosticText() {
    if (_entries.isEmpty) {
      return 'No diagnostic entries recorded.';
    }
    return recentEntries().map((entry) => entry.toDiagnosticLine()).join('\n');
  }

  static void clearDiagnostics() {
    _entries.clear();
  }

  static void _record(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _entries.add(
      AppLogEntry(
        level: level,
        message: _sanitize(message),
        error: error == null ? null : _sanitize(error.toString()),
        stackTrace: stackTrace == null ? null : _compactStackTrace(stackTrace),
        recordedAt: DateTime.now(),
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  static String _compactStackTrace(StackTrace stackTrace) {
    return stackTrace.toString().split('\n').take(8).map(_sanitize).join('\n');
  }

  static String _sanitize(String value) {
    var sanitized = value;
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(access|refresh|id)_token[=:]\s*[^,\s}]+', caseSensitive: false),
      (match) => '${match.group(1)}_token=<redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]*'),
      '<jwt-redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'C:\\Users\\[^\\\s]+'),
      r'C:\Users\<user>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'/Users/[^/\s]+'),
      '/Users/<user>',
    );
    if (sanitized.length > 600) {
      sanitized = '${sanitized.substring(0, 600)}...';
    }
    return sanitized;
  }
}
