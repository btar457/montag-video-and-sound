import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laqta/core/export/export_request.dart';
import 'package:laqta/core/project/clip.dart';
import 'package:laqta/core/project/edit_project.dart';
import 'package:laqta/features/export/export_engine.dart';

const _methods = MethodChannel('app.laqta/export');
const _eventsName = 'app.laqta/export/events';

ExportRequest _request() => ExportRequest.fromProject(
  EditProject(id: 'p', name: 'x').addClip(
    Clip.full(
      id: 'a',
      sourcePath: '/media/a.mp4',
      sourceDuration: const Duration(seconds: 2),
    ),
  ),
  quality: ExportQuality.p720,
  outputPath: '/cache/exports/out.mp4',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Native side stand-in: records calls and replays [events] on listen.
  void fakeNative({
    required List<Object?> events,
    List<MethodCall>? calls,
    PlatformException? startError,
  }) {
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls?.add(call);
      if (call.method == 'start' && startError != null) throw startError;
      return null;
    });
    messenger.setMockStreamHandler(
      const EventChannel(_eventsName),
      MockStreamHandler.inline(
        onListen: (_, sink) {
          for (final e in events) {
            sink.success(e);
          }
        },
      ),
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(const EventChannel(_eventsName), null);
  });

  test('sends the request map and relays progress then done', () async {
    final calls = <MethodCall>[];
    fakeNative(
      calls: calls,
      events: [
        {'type': 'progress', 'fraction': null},
        {'type': 'progress', 'fraction': 0.5},
        {'type': 'done', 'outputPath': '/cache/exports/out.mp4'},
        {'type': 'progress', 'fraction': 0.9}, // after done: ignored
      ],
    );

    final events = await MethodChannelExportEngine().start(_request()).toList();

    expect(calls.single.method, 'start');
    expect(calls.single.arguments, _request().toMap());
    expect(events, hasLength(3));
    expect((events[0] as ExportProgress).fraction, isNull);
    expect((events[1] as ExportProgress).fraction, 0.5);
    expect((events[2] as ExportDone).outputPath, '/cache/exports/out.mp4');
  });

  test('native rejection becomes ExportFailed with its code', () async {
    fakeNative(
      events: [],
      startError: PlatformException(code: 'invalid_input'),
    );
    final events = await MethodChannelExportEngine().start(_request()).toList();
    expect(events, hasLength(1));
    expect((events.single as ExportFailed).code, 'invalid_input');
  });

  test('error and cancelled events end the stream', () async {
    fakeNative(
      events: [
        {'type': 'error', 'code': 'transformer_7001'},
      ],
    );
    var events = await MethodChannelExportEngine().start(_request()).toList();
    expect((events.single as ExportFailed).code, 'transformer_7001');

    fakeNative(
      events: [
        {'type': 'cancelled'},
      ],
    );
    events = await MethodChannelExportEngine().start(_request()).toList();
    expect(events.single, isA<ExportCancelled>());
  });

  test('no message at all from native ends with no_response', () async {
    fakeNative(events: []); // start "succeeds" but nothing ever arrives
    final events = await MethodChannelExportEngine(
      noResponseTimeout: const Duration(milliseconds: 50),
    ).start(_request()).toList();
    expect((events.single as ExportFailed).code, 'no_response');
  });

  test('regular progress keeps the watchdog from firing', () async {
    messenger.setMockMethodCallHandler(_methods, (call) async => null);
    messenger.setMockStreamHandler(
      const EventChannel(_eventsName),
      MockStreamHandler.inline(
        onListen: (_, sink) async {
          for (var i = 0; i < 4; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            sink.success({'type': 'progress', 'fraction': i / 4});
          }
          sink.success({'type': 'done', 'outputPath': '/o.mp4'});
        },
      ),
    );
    final events = await MethodChannelExportEngine(
      noResponseTimeout: const Duration(milliseconds: 60),
    ).start(_request()).toList();
    expect(events.last, isA<ExportDone>());
  });

  test('missing native side reports unsupported_platform', () async {
    messenger.setMockMethodCallHandler(_methods, (call) async {
      throw MissingPluginException();
    });
    messenger.setMockStreamHandler(
      const EventChannel(_eventsName),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    final events = await MethodChannelExportEngine().start(_request()).toList();
    expect((events.single as ExportFailed).code, 'unsupported_platform');
  });

  test('channel error fails the export and stops the native render', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockStreamHandler(
      const EventChannel(_eventsName),
      MockStreamHandler.inline(onListen: (_, sink) => sink.error(code: 'boom')),
    );
    final events = await MethodChannelExportEngine().start(_request()).toList();
    expect((events.single as ExportFailed).code, 'channel_error');
    expect(calls.map((c) => c.method), contains('cancel'));
  });

  test('event subscription is released after the export ends', () async {
    var cancelled = false;
    messenger.setMockMethodCallHandler(_methods, (call) async => null);
    messenger.setMockStreamHandler(
      const EventChannel(_eventsName),
      MockStreamHandler.inline(
        onListen: (_, sink) =>
            sink.success({'type': 'done', 'outputPath': '/o.mp4'}),
        onCancel: (_) => cancelled = true,
      ),
    );
    await MethodChannelExportEngine().start(_request()).toList();
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
  });

  test('cancel never throws even if native fails', () async {
    messenger.setMockMethodCallHandler(_methods, (call) async {
      throw PlatformException(code: 'x');
    });
    await expectLater(MethodChannelExportEngine().cancel(), completes);
  });

  test('cancel calls the native side', () async {
    final calls = <MethodCall>[];
    fakeNative(events: [], calls: calls);
    await MethodChannelExportEngine().cancel();
    expect(calls.single.method, 'cancel');
  });

  group('parseEvent', () {
    test('clamps progress and ignores unknown messages', () {
      expect(
        (MethodChannelExportEngine.parseEvent({
                  'type': 'progress',
                  'fraction': 1.7,
                })!
                as ExportProgress)
            .fraction,
        1.0,
      );
      expect(MethodChannelExportEngine.parseEvent('junk'), isNull);
      expect(MethodChannelExportEngine.parseEvent({'type': 'what'}), isNull);
      expect(MethodChannelExportEngine.parseEvent({'type': 'done'}), isNull);
    });
  });
}
