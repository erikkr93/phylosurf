import 'dart:async';
import 'dart:collection';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../utils/taxon_ipa_phonemizer.dart';
import '../utils/wav_encoder.dart';
import 'kitten_model_manager.dart';
import 'kitten_tts_worker.dart';
import 'taxon_speech_service.dart';

/// Thin testable adapter for playing synthesized in-memory WAV audio.
abstract class WavAudioPlayer {
  void setCompletionHandler(VoidCallback callback);
  Future<void> playWavBytes(Uint8List wavBytes);
  Future<void> stop();
  Future<void> dispose();
}

class _AudioPlayersWavPlayer implements WavAudioPlayer {
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSubscription;
  VoidCallback? _onComplete;
  bool _isDisposed = false;

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) {
      return existing;
    }
    final player = AudioPlayer();
    _player = player;
    _completeSubscription = player.onPlayerComplete.listen((_) {
      if (!_isDisposed) {
        _onComplete?.call();
      }
    });
    return player;
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    _onComplete = callback;
  }

  @override
  Future<void> playWavBytes(Uint8List wavBytes) async {
    if (_isDisposed) return;
    final player = _ensurePlayer();
    await player.play(BytesSource(wavBytes, mimeType: 'audio/wav'));
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null) return;
    await player.stop();
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _onComplete = null;

    final sub = _completeSubscription;
    _completeSubscription = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {
        // Best-effort subscription cleanup.
      }
    }

    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {
        // Best-effort player disposal.
      }
    }
  }
}

/// Hybrid [TaxonSpeechService] that synthesizes scientific names locally with
/// KittenTTS (via [KittenSynthesizer]) and falls back cleanly to a platform
/// [TaxonSpeechService] (defaulting to [FlutterTtsTaxonSpeechService]) on any
/// download, synthesis, or playback failure.
class KittenTaxonSpeechService extends TaxonSpeechService {
  KittenTaxonSpeechService({
    KittenModelManager? modelManager,
    KittenSynthesizer? synthesizer,
    WavAudioPlayer? audioPlayer,
    TaxonSpeechService? fallbackService,
    List<int> Function(String)? phonemizer,
    this._speakerId = 0,
    this._speed = 0.92,
    this._maxCacheEntries = 32,
  }) : _modelManager = modelManager ?? KittenModelManager(),
       _synthesizer = synthesizer ?? KittenTtsWorker(),
       _audioPlayer = audioPlayer ?? _AudioPlayersWavPlayer(),
       _fallbackService = fallbackService ?? FlutterTtsTaxonSpeechService(),
       _ownsFallbackService = fallbackService == null,
       _phonemizer = phonemizer ?? phonemizeScientificNameToKittenCodepoints {
    assert(_maxCacheEntries >= 0);
    _audioPlayer.setCompletionHandler(_handleAudioComplete);
    _fallbackService.addListener(_handleFallbackChanged);
  }

  final KittenModelManager _modelManager;
  final KittenSynthesizer _synthesizer;
  final WavAudioPlayer _audioPlayer;
  final TaxonSpeechService _fallbackService;
  final bool _ownsFallbackService;
  final List<int> Function(String) _phonemizer;
  final int _speakerId;
  final double _speed;
  final int _maxCacheEntries;

  final LinkedHashMap<String, Uint8List> _wavCache =
      LinkedHashMap<String, Uint8List>();

  bool _isSpeaking = false;
  bool _isPreparing = false;
  double? _preparationProgress;
  String? _statusMessage;
  String? _activeScientificName;
  String? _lastError;
  bool _usingFallback = false;
  bool _isDisposed = false;
  int _requestSeq = 0;

  @override
  bool get isSpeaking =>
      _usingFallback ? _fallbackService.isSpeaking : _isSpeaking;

  @override
  bool get isPreparing => _isPreparing;

  @override
  double? get preparationProgress => _preparationProgress;

  @override
  String? get statusMessage => _statusMessage;

  @override
  String? get activeScientificName => _usingFallback
      ? _fallbackService.activeScientificName
      : _activeScientificName;

  @override
  String? get lastError =>
      _usingFallback ? (_fallbackService.lastError ?? _lastError) : _lastError;

  void _handleAudioComplete() {
    if (_isDisposed || _usingFallback || !_isSpeaking) {
      return;
    }
    _isSpeaking = false;
    _activeScientificName = null;
    _safeNotifyListeners();
  }

  void _handleFallbackChanged() {
    if (_isDisposed) {
      return;
    }
    if (_usingFallback) {
      _safeNotifyListeners();
    }
  }

  Uint8List? _getCachedWav(String key) {
    final existing = _wavCache.remove(key);
    if (existing != null) {
      _wavCache[key] = existing;
    }
    return existing;
  }

  void _putCachedWav(String key, Uint8List wavBytes) {
    if (_maxCacheEntries <= 0) {
      return;
    }
    _wavCache.remove(key);
    _wavCache[key] = wavBytes;
    while (_wavCache.length > _maxCacheEntries) {
      _wavCache.remove(_wavCache.keys.first);
    }
  }

  Future<void> _stopActivePlayback() async {
    final wasUsingFallback = _usingFallback;
    final wasSpeaking = _isSpeaking;
    _usingFallback = false;
    _isSpeaking = false;
    _isPreparing = false;
    _preparationProgress = null;
    _statusMessage = null;
    _activeScientificName = null;

    if (wasSpeaking) {
      try {
        await _audioPlayer.stop();
      } catch (_) {
        // Best-effort stop before starting next playback.
      }
    }
    if (wasUsingFallback || _fallbackService.isSpeaking) {
      try {
        await _fallbackService.stop();
      } catch (_) {
        // Best-effort stop of fallback TTS.
      }
    }
  }

  @override
  Future<bool> speakScientificName(String scientificName) async {
    if (_isDisposed) {
      return false;
    }

    final trimmed = scientificName.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final codepoints = _phonemizer(trimmed);
    if (codepoints.isEmpty) {
      return false;
    }

    final seq = ++_requestSeq;

    await _stopActivePlayback();
    if (_isDisposed || seq != _requestSeq) {
      return false;
    }

    final cachedWav = _getCachedWav(trimmed);
    if (cachedWav != null) {
      _isPreparing = false;
      _preparationProgress = null;
      _statusMessage = null;
      _lastError = null;
      _usingFallback = false;
      _activeScientificName = scientificName;
      _isSpeaking = true;
      _safeNotifyListeners();

      try {
        await _audioPlayer.playWavBytes(cachedWav);
        if (_isDisposed || seq != _requestSeq) {
          return false;
        }
        return true;
      } catch (e) {
        return _fallbackAfterError(
          error: e,
          scientificName: scientificName,
          seq: seq,
        );
      }
    }

    _isPreparing = true;
    _preparationProgress = null;
    _activeScientificName = scientificName;
    _lastError = null;
    _statusMessage = 'Preparing natural voice...';
    _usingFallback = false;
    _safeNotifyListeners();

    try {
      final paths = await _modelManager.ensureModelReady(
        onProgress: (progress) {
          if (_isDisposed || seq != _requestSeq) {
            return;
          }
          _isPreparing = true;
          _preparationProgress = progress.fraction;
          _statusMessage = progress.message;
          _safeNotifyListeners();
        },
      );
      if (_isDisposed || seq != _requestSeq) {
        return false;
      }

      if (!_synthesizer.isRunning) {
        await _synthesizer.start(paths);
      }
      if (_isDisposed || seq != _requestSeq) {
        return false;
      }

      _statusMessage = 'Synthesizing pronunciation...';
      _preparationProgress = null;
      _safeNotifyListeners();

      final audio = await _synthesizer.synthesize(
        phonemeCodepoints: codepoints,
        sid: _speakerId,
        speed: _speed,
      );
      if (_isDisposed || seq != _requestSeq) {
        return false;
      }

      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        throw StateError('Empty audio generated');
      }

      final wavBytes = encodeFloat32SamplesToWav(
        audio.samples,
        audio.sampleRate,
      );
      _putCachedWav(trimmed, wavBytes);

      _isPreparing = false;
      _preparationProgress = null;
      _statusMessage = null;
      _isSpeaking = true;
      _activeScientificName = scientificName;
      _safeNotifyListeners();

      await _audioPlayer.playWavBytes(wavBytes);
      if (_isDisposed || seq != _requestSeq) {
        return false;
      }
      return true;
    } catch (e) {
      return _fallbackAfterError(
        error: e,
        scientificName: scientificName,
        seq: seq,
      );
    }
  }

  Future<bool> _fallbackAfterError({
    required Object error,
    required String scientificName,
    required int seq,
  }) async {
    if (_isDisposed || seq != _requestSeq) {
      return false;
    }

    _isPreparing = false;
    _preparationProgress = null;
    _statusMessage = null;
    _isSpeaking = false;
    _activeScientificName = null;
    _lastError = '$error';
    _usingFallback = true;
    _safeNotifyListeners();

    try {
      final ok = await _fallbackService.speakScientificName(scientificName);
      if (_isDisposed || seq != _requestSeq) {
        return false;
      }
      if (!ok) {
        _usingFallback = false;
        _safeNotifyListeners();
      }
      return ok;
    } catch (fallbackError) {
      if (_isDisposed || seq != _requestSeq) {
        return false;
      }
      _usingFallback = false;
      _lastError = '$fallbackError';
      _safeNotifyListeners();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _requestSeq++;
    _isPreparing = false;
    _preparationProgress = null;
    _statusMessage = null;
    _isSpeaking = false;
    _activeScientificName = null;
    _usingFallback = false;

    try {
      await _audioPlayer.stop();
    } catch (_) {
      // Best-effort stop.
    }

    try {
      await _fallbackService.stop();
    } catch (_) {
      // Best-effort stop.
    }

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
    _requestSeq++;
    _isPreparing = false;
    _preparationProgress = null;
    _statusMessage = null;
    _isSpeaking = false;
    _activeScientificName = null;
    _usingFallback = false;

    _fallbackService.removeListener(_handleFallbackChanged);
    if (_ownsFallbackService) {
      try {
        _fallbackService.dispose();
      } catch (_) {
        // Best-effort fallback disposal.
      }
    } else if (_fallbackService.isSpeaking) {
      try {
        unawaited(_fallbackService.stop().catchError((Object _) {}));
      } catch (_) {
        // Best-effort fallback stop.
      }
    }

    try {
      _modelManager.dispose();
    } catch (_) {
      // Best-effort model manager disposal.
    }

    try {
      unawaited(_synthesizer.close().catchError((Object _) {}));
    } catch (_) {
      // Best-effort synthesizer cleanup.
    }

    try {
      unawaited(_audioPlayer.dispose().catchError((Object _) {}));
    } catch (_) {
      // Best-effort audio player cleanup.
    }

    super.dispose();
  }
}
