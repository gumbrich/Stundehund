import 'package:flutter/services.dart';
import 'tracker.dart';

/// Native event time is retained even if Dart receives it after waking up.
class PowerEvents {
  static const channel = MethodChannel('stundehund/power');

  static void listen(Tracker tracker) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'suspend' && call.arguments is int) {
        await tracker.suspend(
          DateTime.fromMillisecondsSinceEpoch(call.arguments as int),
        );
      }
    });
  }

  static void stopListening() => channel.setMethodCallHandler(null);
}
