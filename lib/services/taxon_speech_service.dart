import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../utils/taxon_pronunciation.dart';

/// Contract for pronouncing scientific taxon names via text-to-speech.
abstract class TaxonSpeechService extends ChangeNotifier {
  bool get isSpeaking;
  String? get activeScientificName;
  String? get lastError;

  bool get isPreparing => false;
  double? get preparationProgress => null;
  String? get statusMessage => null;

  Future<bool> speakScientificName(String scientificName);
  Future<void> stop();
}

/// Thin testable adapter around the underlying platform TTS engine.
abstract class TtsEngine {
  Future<bool> isLanguageAvailable(String language);
  Future<void> setLanguage(String language);
  Future<void> setSpeechRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setPitch(double pitch);
  Future<void> speak(String text);
  Future<void> stop();

  void setStartHandler(VoidCallback callback);
  void setCompletionHandler(VoidCallback callback);
  void setCancelHandler(VoidCallback callback);
  void setErrorHandler(void Function(dynamic message) callback);
}

class _FlutterTtsEngine implements TtsEngine {
  _FlutterTtsEngine() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<bool> isLanguageAvailable(String language) async {
    final result = await _tts.isLanguageAvailable(language);
    if (result is bool) {
      return result;
    }
    if (result is int) {
      return result == 1;
    }
    return false;
  }

  @override
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  void setStartHandler(VoidCallback callback) {
    _tts.setStartHandler(callback);
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    _tts.setCompletionHandler(callback);
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    _tts.setCancelHandler(callback);
  }

  @override
  void setErrorHandler(void Function(dynamic message) callback) {
    _tts.setErrorHandler(callback);
  }
}

/// Cross-platform [TaxonSpeechService] backed by `flutter_tts`.
class FlutterTtsTaxonSpeechService extends TaxonSpeechService {
  FlutterTtsTaxonSpeechService({
    this._engine,
    String Function(String)? formatter,
  }) : _formatter = formatter ?? formatScientificNameForAnglicizedTts;

  static const List<String> _preferredLocales = ['en-US', 'en-GB', 'en'];
  static const double _defaultSpeechRate = 0.45;
  static const double _defaultVolume = 1.0;
  static const double _defaultPitch = 1.0;

  TtsEngine? _engine;
  final String Function(String) _formatter;

  Future<TtsEngine>? _configureFuture;
  bool _isSpeaking = false;
  String? _activeScientificName;
  String? _lastError;
  bool _isDisposed = false;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  String? get activeScientificName => _activeScientificName;

  @override
  String? get lastError => _lastError;

  Future<TtsEngine> _ensureConfigured() {
    return _configureFuture ??= _configureEngine();
  }

  Future<TtsEngine> _configureEngine() async {
    final engine = _engine ??= _FlutterTtsEngine();

    engine.setStartHandler(() {
      if (_isDisposed) return;
      _isSpeaking = true;
      _lastError = null;
      _safeNotifyListeners();
    });

    engine.setCompletionHandler(() {
      if (_isDisposed) return;
      _isSpeaking = false;
      _activeScientificName = null;
      _safeNotifyListeners();
    });

    engine.setCancelHandler(() {
      if (_isDisposed) return;
      _isSpeaking = false;
      _activeScientificName = null;
      _safeNotifyListeners();
    });

    engine.setErrorHandler((dynamic message) {
      if (_isDisposed) return;
      _isSpeaking = false;
      _activeScientificName = null;
      _lastError = message?.toString() ?? 'Unknown TTS error';
      _safeNotifyListeners();
    });

    for (final locale in _preferredLocales) {
      try {
        final available = await engine.isLanguageAvailable(locale);
        if (available) {
          await engine.setLanguage(locale);
          break;
        }
      } catch (_) {
        // Ignore unavailable or failing locale checks and try next fallback.
      }
    }

    try {
      await engine.setSpeechRate(_defaultSpeechRate);
    } catch (_) {
      // Ignore platform speech-rate configuration failures.
    }

    try {
      await engine.setVolume(_defaultVolume);
    } catch (_) {
      // Ignore platform volume configuration failures.
    }

    try {
      await engine.setPitch(_defaultPitch);
    } catch (_) {
      // Ignore platform pitch configuration failures.
    }

    return engine;
  }

  @override
  Future<bool> speakScientificName(String scientificName) async {
    if (_isDisposed) {
      return false;
    }

    final formatted = _formatter(scientificName).trim();
    if (formatted.isEmpty) {
      return false;
    }

    final engine = await _ensureConfigured();
    if (_isDisposed) {
      return false;
    }

    if (_isSpeaking) {
      await stop();
      if (_isDisposed) {
        return false;
      }
    }

    _activeScientificName = scientificName;
    _isSpeaking = true;
    _lastError = null;
    _safeNotifyListeners();

    try {
      await engine.speak(formatted);
      return true;
    } catch (e) {
      _isSpeaking = false;
      _activeScientificName = null;
      _lastError = '$e';
      _safeNotifyListeners();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final engine = _engine;
    if (engine != null) {
      try {
        await engine.stop();
      } catch (_) {
        // Best-effort stop; always clear local playback state.
      }
    }
    _isSpeaking = false;
    _activeScientificName = null;
    _safeNotifyListeners();
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    final engine = _engine;
    if (engine != null) {
      try {
        unawaited(engine.stop().catchError((Object _) {}));
      } catch (_) {
        // Best-effort stop during disposal.
      }
    }
    super.dispose();
  }
}
