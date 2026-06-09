import 'dart:async';

import 'app_log.dart';

Future<void> runBackgroundTask(
  String label,
  Future<void> Function() task,
) async {
  try {
    await task();
  } catch (error, stackTrace) {
    AppLog.error(label, error, stackTrace);
  }
}

void unawaitedLogged(String label, Future<void> Function() task) {
  unawaited(runBackgroundTask(label, task));
}
