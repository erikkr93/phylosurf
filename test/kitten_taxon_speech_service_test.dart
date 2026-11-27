import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncbi_taxonomy_explorer/services/kitten_model_manager.dart';
import 'package:ncbi_taxonomy_explorer/services/kitten_taxon_speech_service.dart';
import 'package:ncbi_taxonomy_explorer/services/kitten_tts_worker.dart';
import 'package:ncbi_taxonomy_explorer/services/taxon_speech_service.dart';

final _samplePaths = KittenModelPaths(
  directory: '/tmp/kitten',
  modelPath: '/tmp/kitten/model.onnx',
  voicesPath: '/tmp/kitten/voices.bin',
  tokensPath: '/tmp/kitten/tokens.txt',
);

SynthesizedAudio _sampleAudio({int length = 64, int sampleRate = 24000}) {
  final samples = Float32List(length);
  for (var i = 0; i < length; i++) {
    samples[i] = (i % 8) / 16.0;
  }
  return SynthesizedAudio(samples: samples, sampleRate: sampleRate);
}

class _FakeKittenModelManager extends KittenModelManager {
  int ensureCalls = 0;
  int disposeCalls = 0;
  Object? ensureError;
  List<KittenModelProgress> progressEvents = <KittenModelProgress>[];
  Future<KittenModelPaths> Function(
    void Function(KittenModelProgress progress)? onProgress,
  )?
  onEnsureModelReady;

  @override
  Future<KittenModelPaths?> getReadyModelPaths() async => _samplePaths;

  @override
  Future<KittenModelPaths> ensureModelReady({
    void Function(KittenModelProgress progress)? onProgress,
  }) async {
    ensureCalls++;
    final handler = onEnsureModelReady;
    if (handler != null) {
      return handler(onProgress);
    }
    for (final event in progressEvents) {
      onProgress?.call(event);
    }
    if (ensureError != null) {
      throw ensureError!;
    }
    return _samplePaths;
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

class _SynthesisRequest {
  const _SynthesisRequest({
    required this.codepoints,
    required this.sid,
    required this.speed,
  });

  final List<int> codepoints;
  final int sid;
  final double speed;
}

class _FakeKittenSynthesizer implements KittenSynthesizer {
  bool _running = false;
  int startCalls = 0;
  int closeCalls = 0;
  final List<_SynthesisRequest> requests = <_SynthesisRequest>[];

  Object? startError;
  Object? synthesizeError;
  Object? closeError;
  Future<SynthesizedAudio> Function(
    List<int> phonemeCodepoints,
    int sid,
    double speed,
  )?
  onSynthesize;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start(KittenModelPaths paths) async {
    startCalls++;
    if (startError != null) {
      throw startError!;
    }
    _running = true;
  }

  @override
  Future<SynthesizedAudio> synthesize({
    required List<int> phonemeCodepoints,
    int sid = 0,
    double speed = 0.92,
  }) async {
    requests.add(
      _SynthesisRequest(
        codepoints: List<int>.from(phonemeCodepoints),
        sid: sid,
        speed: speed,
      ),
    );
    if (synthesizeError != null) {
      throw synthesizeError!;
    }
    final handler = onSynthesize;
    if (handler != null) {
      return handler(phonemeCodepoints, sid, speed);
    }
    return _sampleAudio();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    _running = false;
    if (closeError != null) {
      throw closeError!;
    }
  }
}

class _FakeWavAudioPlayer implements WavAudioPlayer {
  VoidCallback? onComplete;
  final List<Uint8List> playedWavBytes = <Uint8List>[];
  int stopCalls = 0;
  int disposeCalls = 0;
  Object? playError;
  Object? stopError;
  Object? disposeError;

  @override
  void setCompletionHandler(VoidCallback callback) {
    onComplete = callback;
  }

  @override
  Future<void> playWavBytes(Uint8List wavBytes) async {
    if (playError != null) {
      throw playError!;
    }
    playedWavBytes.add(wavBytes);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopError != null) {
      throw stopError!;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (disposeError != null) {
      throw disposeError!;
    }
  }
}

class _FakeFallbackSpeechService extends TaxonSpeechService {
  bool _isSpeaking = false;
  String? _activeScientificName;
  String? _lastError;

  final List<String> spokenNames = <String>[];
  int stopCalls = 0;
  int disposeCalls = 0;
  bool speakResult = true;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  String? get activeScientificName => _activeScientificName;

  @override
  String? get lastError => _lastError;

  @override
  Future<bool> speakScientificName(String scientificName) async {
    spokenNames.add(scientificName);
    if (!speakResult) {
      _isSpeaking = false;
      _activeScientificName = null;
      _lastError = 'Fallback failed';
      notifyListeners();
      return false;
    }
    _isSpeaking = true;
    _activeScientificName = scientificName;
    _lastError = null;
    notifyListeners();
    return true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _isSpeaking = false;
    _activeScientificName = null;
    notifyListeners();
  }

  void simulateCompletion() {
    _isSpeaking = false;
    _activeScientificName = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

void main() {
  group('KittenTaxonSpeechService', () {
    test(
      'prepares model with progress, synthesizes IPA codepoints, plays WAV, and resets on completion',
      () async {
        final modelManager = _FakeKittenModelManager()
          ..progressEvents = <KittenModelProgress>[
            KittenModelProgress(
              stage: KittenModelStage.downloading,
              message: 'Downloading voice model...',
              fraction: 0.25,
            ),
            KittenModelProgress(
              stage: KittenModelStage.extracting,
              message: 'Extracting voice model...',
              fraction: 0.85,
            ),
          ];
        final synthesizer = _FakeKittenSynthesizer();
        final player = _FakeWavAudioPlayer();
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
          speakerId: 2,
          speed: 0.9,
        );
        addTearDown(() {
          service.dispose();
          fallback.dispose();
        });

        final seenProgress = <double?>[];
        final seenStatuses = <String?>[];
        var sawPreparing = false;
        service.addListener(() {
          if (service.isPreparing) {
            sawPreparing = true;
            seenProgress.add(service.preparationProgress);
            seenStatuses.add(service.statusMessage);
          }
        });

        final ok = await service.speakScientificName('Homo sapiens');

        expect(ok, isTrue);
        expect(sawPreparing, isTrue);
        expect(seenProgress, containsAllInOrder(<double?>[0.25, 0.85]));
        expect(
          seenStatuses,
          containsAll(<String?>[
            'Downloading voice model...',
            'Extracting voice model...',
            'Synthesizing pronunciation...',
          ]),
        );

        expect(modelManager.ensureCalls, 1);
        expect(synthesizer.startCalls, 1);
        expect(synthesizer.requests, hasLength(1));
        expect(synthesizer.requests.single.codepoints, 'Homo sapiens'.codeUnits);
        expect(synthesizer.requests.single.sid, 2);
        expect(synthesizer.requests.single.speed, 0.9);

        expect(player.playedWavBytes, hasLength(1));
        final wav = player.playedWavBytes.single;
        expect(wav.length, greaterThan(44));
        expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');

        expect(service.isPreparing, isFalse);
        expect(service.preparationProgress, isNull);
        expect(service.statusMessage, isNull);
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Homo sapiens');
        expect(service.lastError, isNull);
        expect(fallback.spokenNames, isEmpty);

        player.onComplete!();
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);
      },
    );

    test(
      'reuses cached WAV bytes on repeat speak without re-synthesizing',
      () async {
        final modelManager = _FakeKittenModelManager();
        final synthesizer = _FakeKittenSynthesizer();
        final player = _FakeWavAudioPlayer();
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
        );
        addTearDown(() {
          service.dispose();
          fallback.dispose();
        });

        expect(await service.speakScientificName('Escherichia coli'), isTrue);
        expect(synthesizer.requests, hasLength(1));
        expect(player.playedWavBytes, hasLength(1));

        player.onComplete!();

        expect(await service.speakScientificName('Escherichia coli'), isTrue);
        expect(modelManager.ensureCalls, 1);
        expect(synthesizer.requests, hasLength(1));
        expect(player.playedWavBytes, hasLength(2));
        expect(player.playedWavBytes[1], equals(player.playedWavBytes[0]));
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Escherichia coli');
        expect(service.isPreparing, isFalse);
      },
    );

    test(
      'calling stop during in-flight model preparation prevents stale playback',
      () async {
        final modelCompleter = Completer<KittenModelPaths>();
        final modelManager = _FakeKittenModelManager()
          ..onEnsureModelReady = (onProgress) {
            onProgress?.call(
              KittenModelProgress(
                stage: KittenModelStage.downloading,
                message: 'Downloading voice model...',
                fraction: 0.4,
              ),
            );
            return modelCompleter.future;
          };
        final synthesizer = _FakeKittenSynthesizer();
        final player = _FakeWavAudioPlayer();
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
        );
        addTearDown(() {
          service.dispose();
          fallback.dispose();
        });

        final speakFuture = service.speakScientificName('Quercus robur');
        await Future<void>.delayed(Duration.zero);

        expect(service.isPreparing, isTrue);
        expect(service.preparationProgress, 0.4);
        expect(service.activeScientificName, 'Quercus robur');

        await service.stop();
        expect(service.isPreparing, isFalse);
        expect(service.preparationProgress, isNull);
        expect(service.statusMessage, isNull);
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);

        modelCompleter.complete(_samplePaths);
        final ok = await speakFuture;

        expect(ok, isFalse);
        expect(synthesizer.startCalls, 0);
        expect(synthesizer.requests, isEmpty);
        expect(player.playedWavBytes, isEmpty);
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);
      },
    );

    test(
      'switching to another scientific name mid-synthesis discards stale first result',
      () async {
        final firstSynthCompleter = Completer<SynthesizedAudio>();
        final secondSynthCompleter = Completer<SynthesizedAudio>();
        var synthCount = 0;

        final modelManager = _FakeKittenModelManager();
        final synthesizer = _FakeKittenSynthesizer()
          ..onSynthesize = (codepoints, sid, speed) {
            synthCount++;
            if (synthCount == 1) {
              return firstSynthCompleter.future;
            }
            return secondSynthCompleter.future;
          };
        final player = _FakeWavAudioPlayer();
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
        );
        addTearDown(() {
          service.dispose();
          fallback.dispose();
        });

        final firstFuture = service.speakScientificName('Panthera leo');
        await Future<void>.delayed(Duration.zero);
        expect(synthesizer.requests, hasLength(1));

        final secondFuture = service.speakScientificName('Panthera tigris');
        await Future<void>.delayed(Duration.zero);
        expect(synthesizer.requests, hasLength(2));

        // First synthesis finishes late; its audio must be ignored.
        firstSynthCompleter.complete(_sampleAudio(length: 32));
        expect(await firstFuture, isFalse);
        expect(player.playedWavBytes, isEmpty);

        // Second synthesis completes and plays.
        secondSynthCompleter.complete(_sampleAudio(length: 96));
        expect(await secondFuture, isTrue);
        expect(player.playedWavBytes, hasLength(1));
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Panthera tigris');
      },
    );

    test(
      'falls back cleanly to fallbackService when model download fails',
      () async {
        final modelManager = _FakeKittenModelManager()
          ..ensureError = StateError('Offline: cannot download model');
        final synthesizer = _FakeKittenSynthesizer();
        final player = _FakeWavAudioPlayer();
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
        );
        addTearDown(() {
          service.dispose();
          fallback.dispose();
        });

        var notifications = 0;
        service.addListener(() => notifications++);

        final ok = await service.speakScientificName('Ginkgo biloba');

        expect(ok, isTrue);
        expect(fallback.spokenNames, <String>['Ginkgo biloba']);
        expect(player.playedWavBytes, isEmpty);
        expect(service.isPreparing, isFalse);
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Ginkgo biloba');
        expect(service.lastError, contains('Offline: cannot download model'));

        final beforeCompleteNotifications = notifications;
        fallback.simulateCompletion();
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);
        expect(notifications, greaterThan(beforeCompleteNotifications));
      },
    );

    test(
      'falls back cleanly to fallbackService when synthesis throws',
      () async {
        final modelManager = _FakeKittenModelManager();
        final synthesizer = _FakeKittenSynthesizer()
          ..synthesizeError = StateError('ONNX runtime failure');
        final player = _FakeWavAudioPlayer();
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
        );
        addTearDown(() {
          service.dispose();
          fallback.dispose();
        });

        final ok = await service.speakScientificName('Canis lupus');

        expect(ok, isTrue);
        expect(fallback.spokenNames, <String>['Canis lupus']);
        expect(player.playedWavBytes, isEmpty);
        expect(service.isPreparing, isFalse);
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Canis lupus');
        expect(service.lastError, contains('ONNX runtime failure'));
      },
    );

    test('returns false without side effects for blank or empty phonemes', () async {
      final modelManager = _FakeKittenModelManager();
      final synthesizer = _FakeKittenSynthesizer();
      final player = _FakeWavAudioPlayer();
      final fallback = _FakeFallbackSpeechService();

      final service = KittenTaxonSpeechService(
        modelManager: modelManager,
        synthesizer: synthesizer,
        audioPlayer: player,
        fallbackService: fallback,
        phonemizer: (name) => name == '???' ? const <int>[] : name.codeUnits,
      );
      addTearDown(() {
        service.dispose();
        fallback.dispose();
      });

      expect(await service.speakScientificName('   '), isFalse);
      expect(await service.speakScientificName('???'), isFalse);
      expect(modelManager.ensureCalls, 0);
      expect(synthesizer.requests, isEmpty);
      expect(player.playedWavBytes, isEmpty);
      expect(fallback.spokenNames, isEmpty);
    });

    test(
      'dispose cleans up resources safely without throwing or notifying after dispose',
      () async {
        final modelManager = _FakeKittenModelManager();
        final synthesizer = _FakeKittenSynthesizer()
          ..closeError = StateError('Close failure');
        final player = _FakeWavAudioPlayer()
          ..disposeError = StateError('Player dispose failure');
        final fallback = _FakeFallbackSpeechService();

        final service = KittenTaxonSpeechService(
          modelManager: modelManager,
          synthesizer: synthesizer,
          audioPlayer: player,
          fallbackService: fallback,
          phonemizer: (name) => name.codeUnits,
        );
        addTearDown(fallback.dispose);

        await service.speakScientificName('Felis catus');

        var notificationsAfterDispose = 0;
        service.addListener(() => notificationsAfterDispose++);

        expect(service.dispose, returnsNormally);
        await Future<void>.delayed(Duration.zero);

        expect(modelManager.disposeCalls, 1);
        expect(synthesizer.closeCalls, 1);
        expect(player.disposeCalls, 1);
        // Injected fallback service is owned by the caller, not disposed.
        expect(fallback.disposeCalls, 0);

        // Late player and fallback callbacks must not throw or notify.
        expect(() => player.onComplete?.call(), returnsNormally);
        expect(fallback.simulateCompletion, returnsNormally);
        expect(await service.speakScientificName('Ursus arctos'), isFalse);
        await expectLater(service.stop(), completes);
        expect(notificationsAfterDispose, 0);
      },
    );
  });
}
