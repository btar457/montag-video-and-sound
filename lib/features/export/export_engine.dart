import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export/export_request.dart';

/// Progress of one export.
sealed class ExportEvent {
  const ExportEvent();
}

/// [fraction] is 0..1, or null while the engine cannot estimate it yet.
class ExportProgress extends ExportEvent {
  const ExportProgress(this.fraction);
  final double? fraction;
}

class ExportDone extends ExportEvent {
  const ExportDone(this.outputPath);
  final String outputPath;
}

/// [code] is a stable identifier from the native side (e.g. `invalid_input`,
/// `transformer_error`); never shown raw to users.
class ExportFailed extends ExportEvent {
  const ExportFailed(this.code);
  final String code;
}

class ExportCancelled extends ExportEvent {
  const ExportCancelled();
}

/// Renders an [ExportRequest] into a video file.
abstract interface class ExportEngine {
  /// Starts rendering. The stream ends after [ExportDone], [ExportFailed]
  /// or [ExportCancelled]. Only one export runs at a time.
  ///
  /// Cancelling the stream subscription only stops listening; call [cancel]
  /// to stop the render itself.
  Stream<ExportEvent> start(ExportRequest request);

  /// Stops the running render, if any. Never throws.
  Future<void> cancel();
}

final exportEngineProvider = Provider<ExportEngine>(
  (ref) => MethodChannelExportEngine(),
);

/// Talks to `ExportHandler.kt` (Media3 Transformer).
///
/// Protocol: `start` (args = [ExportRequest.toMap]) and `cancel` on the
/// method channel; the event channel then sends maps with a `type` of
/// `progress` (`fraction`: double or null), `done` (`outputPath`),
/// `error` (`code`) or `cancelled`.
class MethodChannelExportEngine implements ExportEngine {
  MethodChannelExportEngine({
    this._methods = const MethodChannel('app.laqta/export'),
    this._events = const EventChannel('app.laqta/export/events'),
    this._noResponseTimeout = const Duration(seconds: 15),
  });

  final MethodChannel _methods;
  final EventChannel _events;

  /// Native sends progress every 250ms once started. If nothing at all
  /// arrives for this long, give up instead of spinning forever.
  final Duration _noResponseTimeout;

  @override
  Stream<ExportEvent> start(ExportRequest request) {
    late final StreamController<ExportEvent> controller;
    StreamSubscription<Object?>? sub;
    Timer? watchdog;

    void finish(ExportEvent last) {
      if (controller.isClosed) return;
      watchdog?.cancel();
      controller.add(last);
      sub?.cancel();
      controller.close();
    }

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(
        _noResponseTimeout,
        () => finish(const ExportFailed('no_response')),
      );
    }

    controller = StreamController<ExportEvent>(
      onListen: () async {
        // Subscribe before starting so no event is missed.
        sub = _events.receiveBroadcastStream().listen(
          (raw) {
            final event = parseEvent(raw);
            if (event == null) return;
            armWatchdog(); // any message proves the native side is alive
            if (event is ExportProgress) {
              if (!controller.isClosed) controller.add(event);
            } else {
              finish(event);
            }
          },
          onError: (Object _) {
            // The render may still be running natively; stop it so a retry
            // is not refused as busy.
            cancel();
            finish(const ExportFailed('channel_error'));
          },
        );
        try {
          await _methods.invokeMethod<void>('start', request.toMap());
          if (!controller.isClosed) armWatchdog();
        } on PlatformException catch (e) {
          finish(ExportFailed(e.code));
        } on MissingPluginException {
          finish(const ExportFailed('unsupported_platform'));
        }
      },
      onCancel: () {
        watchdog?.cancel();
        return sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    try {
      await _methods.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Nothing is running on this platform.
    } on PlatformException {
      // Native side already cleans up on its own; nothing more to do here.
    }
  }

  /// Decodes one event-channel message; unknown messages return null.
  static ExportEvent? parseEvent(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'progress':
        final f = raw['fraction'];
        return ExportProgress(f is num ? f.toDouble().clamp(0.0, 1.0) : null);
      case 'done':
        final path = raw['outputPath'];
        return path is String ? ExportDone(path) : null;
      case 'error':
        final code = raw['code'];
        return ExportFailed(code is String ? code : 'unknown');
      case 'cancelled':
        return const ExportCancelled();
    }
    return null;
  }
}
