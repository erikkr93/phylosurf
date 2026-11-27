import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'kitten_model_manager.dart';

/// Raw mono float32 PCM waveform produced by [KittenSynthesizer].
class SynthesizedAudio {
  const SynthesizedAudio({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

/// Contract for synthesizing KittenTTS audio from pre-phonemized IPA codepoints.
abstract class KittenSynthesizer {
  bool get isRunning;

  Future<void> start(KittenModelPaths paths);

  Future<SynthesizedAudio> synthesize({
    required List<int> phonemeCodepoints,
    int sid = 0,
    double speed = 0.92,
  });

  Future<void> close();
}

/// Persistent background isolate that loads `sherpa_onnx` once and keeps
/// KittenTTS warm across pronunciation requests.
class KittenTtsWorker implements KittenSynthesizer {
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  KittenModelPaths? _activePaths;
  KittenModelPaths? _startingPaths;
  Future<void>? _startFuture;

  final Map<int, Completer<SynthesizedAudio>> _pending = {};
  int _nextRequestId = 1;
  int _lifecycleEpoch = 0;
  bool _isClosing = false;

  @override
  bool get isRunning => _commandPort != null && !_isClosing;

  static bool _pathsEqual(KittenModelPaths? a, KittenModelPaths? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.directory == b.directory &&
        a.modelPath == b.modelPath &&
        a.voicesPath == b.voicesPath &&
        a.tokensPath == b.tokensPath;
  }

  @override
  Future<void> start(KittenModelPaths paths) {
    if (isRunning && _pathsEqual(_activePaths, paths)) {
      return Future<void>.value();
    }
    final inFlight = _startFuture;
    if (inFlight != null && _pathsEqual(_startingPaths, paths)) {
      return inFlight;
    }

    final future = _startInternal(paths, previousStart: inFlight);
    _startingPaths = paths;
    _startFuture = future;
    future.whenComplete(() {
      if (identical(_startFuture, future)) {
        _startFuture = null;
        _startingPaths = null;
      }
    });
    return future;
  }

  Future<void> _startInternal(
    KittenModelPaths paths, {
    Future<void>? previousStart,
  }) async {
    if (previousStart != null) {
      try {
        await previousStart;
      } catch (_) {
        // Ignore prior startup failure before restarting.
      }
    }

    await close();
    final epoch = ++_lifecycleEpoch;
    _isClosing = false;

    final readyCompleter = Completer<SendPort>();
    final responsePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    _responsePort = responsePort;
    _errorPort = errorPort;
    _exitPort = exitPort;

    responsePort.listen((message) {
      if (epoch != _lifecycleEpoch) return;

      if (message is SendPort) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message);
        }
        return;
      }

      if (message is Map) {
        final type = message['type'];
        if (type == 'init_error') {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(
              StateError(
                message['error'] as String? ??
                    'Failed to initialize KittenTTS worker',
              ),
            );
          }
          return;
        }
        if (type == 'closed') {
          responsePort.close();
          return;
        }

        final id = message['id'] as int?;
        if (id == null) return;
        final completer = _pending.remove(id);
        if (completer == null || completer.isCompleted) return;

        if (type == 'result') {
          final rawSamples = message['samples'];
          final Float32List samples;
          if (rawSamples is TransferableTypedData) {
            samples = rawSamples.materialize().asFloat32List();
          } else if (rawSamples is Float32List) {
            samples = rawSamples;
          } else {
            completer.completeError(
              StateError('Unexpected audio payload from KittenTTS worker'),
            );
            return;
          }
          final sampleRate = message['sampleRate'] as int? ?? 0;
          completer.complete(
            SynthesizedAudio(samples: samples, sampleRate: sampleRate),
          );
        } else if (type == 'error') {
          completer.completeError(
            StateError(
              message['error'] as String? ?? 'KittenTTS synthesis failed',
            ),
          );
        }
      }
    });

    errorPort.listen((dynamic message) {
      if (epoch != _lifecycleEpoch) return;
      final description = message is List && message.isNotEmpty
          ? '${message.first}'
          : '$message';
      final error = StateError('KittenTTS worker crashed: $description');
      if (!readyCompleter.isCompleted) {
        readyCompleter.completeError(error);
      }
      _failPending(error);
    });

    exitPort.listen((_) {
      if (epoch != _lifecycleEpoch) return;
      final error = StateError('KittenTTS worker isolate exited unexpectedly');
      if (!readyCompleter.isCompleted) {
        readyCompleter.completeError(error);
      }
      if (!_isClosing) {
        _commandPort = null;
        _activePaths = null;
        _failPending(error);
      }
    });

    Isolate? spawned;
    try {
      spawned = await Isolate.spawn<_KittenWorkerInit>(
        _kittenWorkerMain,
        _KittenWorkerInit(
          modelPath: paths.modelPath,
          voicesPath: paths.voicesPath,
          tokensPath: paths.tokensPath,
          replyPort: responsePort.sendPort,
        ),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'KittenTtsWorker',
      );
      if (_isClosing || epoch != _lifecycleEpoch) {
        spawned.kill(priority: Isolate.immediate);
        _disposePorts(
          responsePort: responsePort,
          errorPort: errorPort,
          exitPort: exitPort,
        );
        throw StateError('KittenTTS worker closed during startup');
      }
      _isolate = spawned;

      final commandPort = await readyCompleter.future;

      if (_isClosing || epoch != _lifecycleEpoch) {
        spawned.kill(priority: Isolate.immediate);
        _disposePorts(
          responsePort: responsePort,
          errorPort: errorPort,
          exitPort: exitPort,
        );
        throw StateError('KittenTTS worker closed during startup');
      }

      _commandPort = commandPort;
      _activePaths = paths;
    } catch (_) {
      if (epoch == _lifecycleEpoch) {
        _commandPort = null;
        _activePaths = null;
        _cleanupResources();
      } else {
        spawned?.kill(priority: Isolate.immediate);
        _disposePorts(
          responsePort: responsePort,
          errorPort: errorPort,
          exitPort: exitPort,
        );
      }
      rethrow;
    }
  }

  @override
  Future<SynthesizedAudio> synthesize({
    required List<int> phonemeCodepoints,
    int sid = 0,
    double speed = 0.92,
  }) {
    final port = _commandPort;
    if (port == null || _isClosing) {
      return Future<SynthesizedAudio>.error(
        StateError('KittenTTS worker is not running'),
      );
    }
    if (phonemeCodepoints.isEmpty) {
      return Future<SynthesizedAudio>.error(
        ArgumentError.value(
          phonemeCodepoints,
          'phonemeCodepoints',
          'must not be empty',
        ),
      );
    }

    final id = _nextRequestId++;
    final completer = Completer<SynthesizedAudio>();
    _pending[id] = completer;

    port.send({
      'type': 'synthesize',
      'id': id,
      'codepoints': List<int>.from(phonemeCodepoints, growable: false),
      'sid': sid,
      'speed': speed,
    });
    return completer.future;
  }

  @override
  Future<void> close() async {
    _isClosing = true;
    _lifecycleEpoch++;
    _activePaths = null;
    _failPending(StateError('KittenTTS worker closed'));

    final port = _commandPort;
    _commandPort = null;
    if (port != null) {
      final done = Completer<void>();
      final ackPort = ReceivePort();
      ackPort.listen((_) {
        if (!done.isCompleted) done.complete();
        ackPort.close();
      });
      try {
        port.send({'type': 'close', 'ack': ackPort.sendPort});
        await done.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => ackPort.close(),
        );
      } catch (_) {
        ackPort.close();
      }
    }

    _cleanupResources();
  }

  void _failPending(Object error) {
    if (_pending.isEmpty) return;
    final completers = _pending.values.toList();
    _pending.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  void _cleanupResources() {
    _responsePort?.close();
    _responsePort = null;
    _errorPort?.close();
    _errorPort = null;
    _exitPort?.close();
    _exitPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void _disposePorts({
    required ReceivePort responsePort,
    required ReceivePort errorPort,
    required ReceivePort exitPort,
  }) {
    responsePort.close();
    errorPort.close();
    exitPort.close();
  }
}

class _KittenWorkerInit {
  const _KittenWorkerInit({
    required this.modelPath,
    required this.voicesPath,
    required this.tokensPath,
    required this.replyPort,
  });

  final String modelPath;
  final String voicesPath;
  final String tokensPath;
  final SendPort replyPort;
}

void _kittenWorkerMain(_KittenWorkerInit init) {
  final commandPort = ReceivePort();
  sherpa_onnx.OfflineTts? tts;

  try {
    if (Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        DynamicLibrary.open(p.join(exeDir, 'onnxruntime.dll'));
      } catch (_) {
        // Best-effort preload so the app's bundled ORT DLL takes precedence
        // over C:\Windows\System32\onnxruntime.dll.
      }
    }

    sherpa_onnx.initBindings();
    tts = sherpa_onnx.OfflineTts(
      sherpa_onnx.OfflineTtsConfig(
        model: sherpa_onnx.OfflineTtsModelConfig(
          kitten: sherpa_onnx.OfflineTtsKittenModelConfig(
            model: init.modelPath,
            voices: init.voicesPath,
            tokens: init.tokensPath,
          ),
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
      ),
    );
  } catch (e) {
    init.replyPort.send({'type': 'init_error', 'error': '$e'});
    commandPort.close();
    return;
  }

  init.replyPort.send(commandPort.sendPort);

  commandPort.listen((message) {
    if (message is! Map) return;
    final type = message['type'];

    if (type == 'close') {
      try {
        tts?.free();
      } catch (_) {
        // Best-effort native release.
      }
      tts = null;
      commandPort.close();
      final ack = message['ack'] as SendPort?;
      ack?.send(true);
      init.replyPort.send({'type': 'closed'});
      return;
    }

    if (type == 'synthesize') {
      final id = message['id'] as int;
      try {
        final engine = tts;
        if (engine == null) {
          init.replyPort.send({
            'type': 'error',
            'id': id,
            'error': 'KittenTTS engine has been freed',
          });
          return;
        }
        final codepoints = (message['codepoints'] as List).cast<int>();
        final sid = message['sid'] as int? ?? 0;
        final speed = (message['speed'] as num?)?.toDouble() ?? 0.92;

        final audio = engine.generateWithConfig(
          text: '',
          config: sherpa_onnx.OfflineTtsGenerationConfig(
            sid: sid,
            speed: speed,
            phonemeCodepoints: [codepoints],
          ),
        );

        init.replyPort.send({
          'type': 'result',
          'id': id,
          'samples': TransferableTypedData.fromList([audio.samples]),
          'sampleRate': audio.sampleRate,
        });
      } catch (e) {
        init.replyPort.send({'type': 'error', 'id': id, 'error': '$e'});
      }
    }
  });
}
