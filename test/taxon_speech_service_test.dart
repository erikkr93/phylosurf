import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncbi_taxonomy_explorer/services/taxon_speech_service.dart';

class FakeTtsEngine implements TtsEngine {
  FakeTtsEngine({
    Set<String>? availableLanguages,
    Set<String>? failingLanguageChecks,
  }) : availableLanguages = availableLanguages ?? {'en-US'},
       failingLanguageChecks = failingLanguageChecks ?? <String>{};

  final Set<String> availableLanguages;
  final Set<String> failingLanguageChecks;

  bool throwOnSetSpeechRate = false;
  bool throwOnSetVolume = false;
  bool throwOnSetPitch = false;
  Object? speakError;
  Object? stopError;
  bool throwStopSynchronously = false;

  final List<String> checkedLanguages = <String>[];
  final List<String> selectedLanguages = <String>[];
  final List<double> speechRates = <double>[];
  final List<double> volumes = <double>[];
  final List<double> pitches = <double>[];
  final List<String> spokenTexts = <String>[];
  final List<String> callLog = <String>[];
  int stopCount = 0;

  VoidCallback? onStart;
  VoidCallback? onCompletion;
  VoidCallback? onCancel;
  void Function(dynamic message)? onError;

  @override
  Future<bool> isLanguageAvailable(String language) async {
    checkedLanguages.add(language);
    callLog.add('isLanguageAvailable:$language');
    if (failingLanguageChecks.contains(language)) {
      throw StateError('Failed to query $language');
    }
    return availableLanguages.contains(language);
  }

  @override
  Future<void> setLanguage(String language) async {
    selectedLanguages.add(language);
    callLog.add('setLanguage:$language');
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    callLog.add('setSpeechRate:$rate');
    if (throwOnSetSpeechRate) {
      throw StateError('Speech rate unsupported');
    }
    speechRates.add(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    callLog.add('setVolume:$volume');
    if (throwOnSetVolume) {
      throw StateError('Volume unsupported');
    }
    volumes.add(volume);
  }

  @override
  Future<void> setPitch(double pitch) async {
    callLog.add('setPitch:$pitch');
    if (throwOnSetPitch) {
      throw StateError('Pitch unsupported');
    }
    pitches.add(pitch);
  }

  @override
  Future<void> speak(String text) async {
    callLog.add('speak:$text');
    if (speakError != null) {
      throw speakError!;
    }
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() {
    stopCount++;
    callLog.add('stop');
    if (throwStopSynchronously && stopError != null) {
      throw stopError!;
    }
    if (stopError != null) {
      return Future<void>.error(stopError!);
    }
    return Future<void>.value();
  }

  @override
  void setStartHandler(VoidCallback callback) {
    onStart = callback;
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    onCompletion = callback;
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    onCancel = callback;
  }

  @override
  void setErrorHandler(void Function(dynamic message) callback) {
    onError = callback;
  }
}

void main() {
  group('FlutterTtsTaxonSpeechService', () {
    test('lazily configures engine once on first speak and selects en-US', () async {
      final engine = FakeTtsEngine(availableLanguages: {'en-US', 'en-GB'});
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      expect(engine.callLog, isEmpty);
      expect(engine.onStart, isNull);
      expect(engine.onCompletion, isNull);
      expect(engine.onCancel, isNull);
      expect(engine.onError, isNull);

      final firstResult = await service.speakScientificName('Homo sapiens');
      expect(firstResult, isTrue);
      expect(engine.checkedLanguages, ['en-US']);
      expect(engine.selectedLanguages, ['en-US']);
      expect(engine.speechRates, [0.45]);
      expect(engine.volumes, [1.0]);
      expect(engine.pitches, [1.0]);
      expect(engine.onStart, isNotNull);
      expect(engine.onCompletion, isNotNull);
      expect(engine.onCancel, isNotNull);
      expect(engine.onError, isNotNull);

      engine.onCompletion!();
      final secondResult = await service.speakScientificName('Pan troglodytes');
      expect(secondResult, isTrue);

      // Configuration runs only once across multiple speak calls.
      expect(engine.checkedLanguages, ['en-US']);
      expect(engine.selectedLanguages, ['en-US']);
      expect(engine.speechRates, [0.45]);
      expect(engine.volumes, [1.0]);
      expect(engine.pitches, [1.0]);
      expect(engine.spokenTexts, ['Homo sapiens', 'Pan troglodytes']);
    });

    test('falls back to en-GB when en-US is unavailable', () async {
      final engine = FakeTtsEngine(availableLanguages: {'en-GB'});
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      final ok = await service.speakScientificName('Quercus robur');
      expect(ok, isTrue);
      expect(engine.checkedLanguages, ['en-US', 'en-GB']);
      expect(engine.selectedLanguages, ['en-GB']);
    });

    test('falls back to en when en-US throws and en-GB is unavailable', () async {
      final engine = FakeTtsEngine(
        availableLanguages: {'en'},
        failingLanguageChecks: {'en-US'},
      );
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      final ok = await service.speakScientificName('Felis catus');
      expect(ok, isTrue);
      expect(engine.checkedLanguages, ['en-US', 'en-GB', 'en']);
      expect(engine.selectedLanguages, ['en']);
    });

    test('tolerates rate, volume, and pitch configuration errors', () async {
      final engine = FakeTtsEngine()
        ..throwOnSetSpeechRate = true
        ..throwOnSetVolume = true
        ..throwOnSetPitch = true;
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      final ok = await service.speakScientificName('Ginkgo biloba');
      expect(ok, isTrue);
      expect(engine.spokenTexts, ['Ginkgo biloba']);
      expect(service.isSpeaking, isTrue);
      expect(service.lastError, isNull);
    });

    test(
      'speaks formatted text and updates state on start, completion, cancel, and error',
      () async {
        final engine = FakeTtsEngine();
        final service = FlutterTtsTaxonSpeechService(
          engine: engine,
          formatter: (name) => 'formatted $name',
        );
        addTearDown(service.dispose);

        var notifications = 0;
        service.addListener(() => notifications++);

        final ok = await service.speakScientificName('Escherichia coli');
        expect(ok, isTrue);
        expect(engine.spokenTexts, ['formatted Escherichia coli']);
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Escherichia coli');
        expect(service.lastError, isNull);
        expect(notifications, 1);

        engine.onStart!();
        expect(service.isSpeaking, isTrue);
        expect(service.lastError, isNull);
        expect(notifications, 2);

        engine.onCompletion!();
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);
        expect(notifications, 3);

        await service.speakScientificName('Drosophila melanogaster');
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Drosophila melanogaster');

        engine.onCancel!();
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);

        await service.speakScientificName('Danio rerio');
        engine.onError!('Audio backend failed');
        expect(service.isSpeaking, isFalse);
        expect(service.activeScientificName, isNull);
        expect(service.lastError, 'Audio backend failed');

        // A new successful speak clears the prior error.
        await service.speakScientificName('Mus musculus');
        expect(service.isSpeaking, isTrue);
        expect(service.activeScientificName, 'Mus musculus');
        expect(service.lastError, isNull);
      },
    );

    test('stops prior playback before speaking when already speaking', () async {
      final engine = FakeTtsEngine();
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      expect(await service.speakScientificName('Homo sapiens'), isTrue);
      expect(service.isSpeaking, isTrue);
      expect(service.activeScientificName, 'Homo sapiens');

      expect(await service.speakScientificName('Pan troglodytes'), isTrue);
      expect(engine.stopCount, 1);
      expect(service.isSpeaking, isTrue);
      expect(service.activeScientificName, 'Pan troglodytes');

      final firstSpeakIdx = engine.callLog.indexOf('speak:Homo sapiens');
      final stopIdx = engine.callLog.indexOf('stop');
      final secondSpeakIdx = engine.callLog.indexOf('speak:Pan troglodytes');
      expect(firstSpeakIdx, greaterThanOrEqualTo(0));
      expect(stopIdx, greaterThan(firstSpeakIdx));
      expect(secondSpeakIdx, greaterThan(stopIdx));
    });

    test('returns false without invoking engine for blank input', () async {
      final engine = FakeTtsEngine();
      final service = FlutterTtsTaxonSpeechService(engine: engine);
      addTearDown(service.dispose);

      var notifications = 0;
      service.addListener(() => notifications++);

      expect(await service.speakScientificName(''), isFalse);
      expect(await service.speakScientificName('   \t\n  '), isFalse);
      expect(engine.callLog, isEmpty);
      expect(service.isSpeaking, isFalse);
      expect(service.activeScientificName, isNull);
      expect(service.lastError, isNull);
      expect(notifications, 0);
    });

    test('catches engine speak exceptions, sets lastError, and resets state', () async {
      final engine = FakeTtsEngine()
        ..speakError = StateError('Engine not ready');
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      var notifications = 0;
      service.addListener(() => notifications++);

      final ok = await service.speakScientificName('Canis lupus');
      expect(ok, isFalse);
      expect(service.isSpeaking, isFalse);
      expect(service.activeScientificName, isNull);
      expect(service.lastError, contains('Engine not ready'));
      expect(notifications, 2);
    });

    test('stop clears state and notifies safely even if engine stop throws', () async {
      final engine = FakeTtsEngine();
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );
      addTearDown(service.dispose);

      await service.speakScientificName('Ursus arctos');
      expect(service.isSpeaking, isTrue);

      var notifications = 0;
      service.addListener(() => notifications++);

      engine.stopError = Exception('Stop failed');
      await expectLater(service.stop(), completes);

      expect(engine.stopCount, 1);
      expect(service.isSpeaking, isFalse);
      expect(service.activeScientificName, isNull);
      expect(notifications, 1);
    });

    test('dispose stops engine safely and ignores subsequent callbacks', () async {
      final engine = FakeTtsEngine();
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );

      await service.speakScientificName('Panthera leo');

      var notificationsAfterDispose = 0;
      service.addListener(() => notificationsAfterDispose++);

      engine.stopError = Exception('Async stop failure on dispose');
      expect(service.dispose, returnsNormally);
      // Allow any async stop error handler microtasks to flush cleanly.
      await Future<void>.delayed(Duration.zero);

      expect(engine.stopCount, 1);
      expect(() => engine.onStart?.call(), returnsNormally);
      expect(() => engine.onCompletion?.call(), returnsNormally);
      expect(() => engine.onCancel?.call(), returnsNormally);
      expect(() => engine.onError?.call('Late error'), returnsNormally);
      expect(await service.speakScientificName('Panthera tigris'), isFalse);
      await expectLater(service.stop(), completes);
      expect(notificationsAfterDispose, 0);
    });

    test('dispose handles synchronous stop exception without throwing', () async {
      final engine = FakeTtsEngine();
      final service = FlutterTtsTaxonSpeechService(
        engine: engine,
        formatter: (name) => name,
      );

      await service.speakScientificName('Balaenoptera musculus');
      engine
        ..stopError = StateError('Sync stop failure')
        ..throwStopSynchronously = true;

      expect(service.dispose, returnsNormally);
      expect(engine.stopCount, 1);
    });
  });
}
