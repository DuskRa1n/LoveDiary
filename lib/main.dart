import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'utils/app_log.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLog.error(
          'Flutter framework error',
          details.exception,
          details.stack,
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        AppLog.error('Unhandled platform error', error, stackTrace);
        return true;
      };
      runApp(const LoveDailyApp());
    },
    (error, stackTrace) {
      AppLog.error('Unhandled zone error', error, stackTrace);
    },
  );
}
