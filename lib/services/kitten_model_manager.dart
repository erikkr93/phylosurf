import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum KittenModelStage { checking, downloading, extracting, ready }

class KittenModelProgress {
  const KittenModelProgress({
    required this.stage,
    required this.message,
    this.fraction,
  });

  final KittenModelStage stage;
  final String message;
  final double? fraction;
}

class KittenModelPaths {
  const KittenModelPaths({
    required this.directory,
    required this.modelPath,
    required this.voicesPath,
    required this.tokensPath,
  });

  final String directory;
  final String modelPath;
  final String voicesPath;
  final String tokensPath;
}

class KittenModelManager {
  static const String modelId = 'kitten-nano-en-v0_2-fp16';
  static const String modelFileName = 'model.fp16.onnx';
  static const String voicesFileName = 'voices.bin';
  static const String tokensFileName = 'tokens.txt';

  static final Uri defaultDownloadUri = Uri.parse(
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_2-fp16.tar.bz2',
  );

  KittenModelManager({
    http.Client? client,
    Future<Directory> Function()? baseDirProvider,
    Uri? downloadUri,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseDirProvider = baseDirProvider ?? getApplicationSupportDirectory,
       _downloadUri = downloadUri ?? defaultDownloadUri;

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _baseDirProvider;
  final Uri _downloadUri;

  Future<KittenModelPaths>? _inFlightEnsure;
  final List<void Function(KittenModelProgress progress)> _progressListeners =
      [];

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Returns the cached [KittenModelPaths] if all required model files exist
  /// and are non-empty, or `null` otherwise.
  Future<KittenModelPaths?> getReadyModelPaths() async {
    final modelsRoot = await _resolveModelsRoot();
    final targetDir = p.join(modelsRoot.path, modelId);
    final paths = _pathsForDirectory(targetDir);

    if (await _isNonEmptyFile(paths.modelPath) &&
        await _isNonEmptyFile(paths.voicesPath) &&
        await _isNonEmptyFile(paths.tokensPath)) {
      return paths;
    }
    return null;
  }

  /// Ensures the KittenTTS Nano model files are downloaded, extracted, and
  /// ready on disk. Concurrent calls share a single in-flight operation.
  Future<KittenModelPaths> ensureModelReady({
    void Function(KittenModelProgress progress)? onProgress,
  }) async {
    if (onProgress != null) {
      _progressListeners.add(onProgress);
    }

    final existing = _inFlightEnsure;
    if (existing != null) {
      try {
        return await existing;
      } finally {
        if (onProgress != null) {
          _progressListeners.remove(onProgress);
        }
      }
    }

    final future = _ensureModelReadyInternal();
    _inFlightEnsure = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightEnsure, future)) {
        _inFlightEnsure = null;
      }
      if (onProgress != null) {
        _progressListeners.remove(onProgress);
      }
    }
  }

  Future<KittenModelPaths> _ensureModelReadyInternal() async {
    _emitProgress(
      const KittenModelProgress(
        stage: KittenModelStage.checking,
        message: 'Checking KittenTTS voice model...',
      ),
    );

    final cached = await getReadyModelPaths();
    if (cached != null) {
      _emitProgress(
        const KittenModelProgress(
          stage: KittenModelStage.ready,
          message: 'Voice model ready.',
          fraction: 1.0,
        ),
      );
      return cached;
    }

    final modelsRoot = await _resolveModelsRoot();
    if (!modelsRoot.existsSync()) {
      await modelsRoot.create(recursive: true);
    }

    final archivePartFile = File(
      p.join(modelsRoot.path, '$modelId.tar.bz2.part'),
    );
    final tempTarFile = File(p.join(modelsRoot.path, '$modelId.tar.part'));
    final stagingDir = Directory(p.join(modelsRoot.path, '$modelId.staging'));
    final targetDir = Directory(p.join(modelsRoot.path, modelId));

    try {
      if (archivePartFile.existsSync()) {
        await archivePartFile.delete();
      }
      if (tempTarFile.existsSync()) {
        await tempTarFile.delete();
      }
      if (stagingDir.existsSync()) {
        await stagingDir.delete(recursive: true);
      }

      _emitProgress(
        const KittenModelProgress(
          stage: KittenModelStage.downloading,
          message: 'Downloading voice model...',
          fraction: 0.0,
        ),
      );

      final request = http.Request('GET', _downloadUri);
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw HttpException(
          'Failed to download KittenTTS model (HTTP ${response.statusCode})',
          uri: _downloadUri,
        );
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final sink = archivePartFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          final mb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final double? fraction = (totalBytes != null && totalBytes > 0)
              ? (receivedBytes / totalBytes).clamp(0.0, 1.0) * 0.85
              : null;
          final totalLabel = (totalBytes != null && totalBytes > 0)
              ? ' / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
              : ' MB';

          _emitProgress(
            KittenModelProgress(
              stage: KittenModelStage.downloading,
              message: 'Downloading voice model ($mb$totalLabel)...',
              fraction: fraction,
            ),
          );
        }
      } finally {
        await sink.close();
      }

      _emitProgress(
        const KittenModelProgress(
          stage: KittenModelStage.extracting,
          message: 'Extracting voice model files...',
          fraction: 0.9,
        ),
      );

      final archivePath = archivePartFile.path;
      final stagingPath = stagingDir.path;
      final tempTarPath = tempTarFile.path;
      await Isolate.run(
        () => _extractRequiredModelFiles(
          archivePath: archivePath,
          stagingDirPath: stagingPath,
          tempTarPath: tempTarPath,
        ),
      );

      if (targetDir.existsSync()) {
        await targetDir.delete(recursive: true);
      }
      await stagingDir.rename(targetDir.path);

      final readyPaths = _pathsForDirectory(targetDir.path);
      _emitProgress(
        const KittenModelProgress(
          stage: KittenModelStage.ready,
          message: 'Voice model ready.',
          fraction: 1.0,
        ),
      );
      return readyPaths;
    } finally {
      if (archivePartFile.existsSync()) {
        try {
          await archivePartFile.delete();
        } catch (_) {}
      }
      if (tempTarFile.existsSync()) {
        try {
          await tempTarFile.delete();
        } catch (_) {}
      }
      if (stagingDir.existsSync()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<Directory> _resolveModelsRoot() async {
    final baseDir = await _baseDirProvider();
    return Directory(p.join(baseDir.path, 'tts_models'));
  }

  KittenModelPaths _pathsForDirectory(String dirPath) {
    return KittenModelPaths(
      directory: dirPath,
      modelPath: p.join(dirPath, modelFileName),
      voicesPath: p.join(dirPath, voicesFileName),
      tokensPath: p.join(dirPath, tokensFileName),
    );
  }

  Future<bool> _isNonEmptyFile(String filePath) async {
    final file = File(filePath);
    return await file.exists() && await file.length() > 0;
  }

  void _emitProgress(KittenModelProgress progress) {
    for (final listener in List.of(_progressListeners)) {
      listener(progress);
    }
  }
}

const Set<String> _requiredModelFileNames = {
  KittenModelManager.modelFileName,
  KittenModelManager.voicesFileName,
  KittenModelManager.tokensFileName,
};

void _extractRequiredModelFiles({
  required String archivePath,
  required String stagingDirPath,
  required String tempTarPath,
}) {
  final stagingDir = Directory(stagingDirPath);
  if (stagingDir.existsSync()) {
    stagingDir.deleteSync(recursive: true);
  }
  stagingDir.createSync(recursive: true);

  final tempTarFile = File(tempTarPath);
  try {
    if (tempTarFile.existsSync()) {
      tempTarFile.deleteSync();
    }

    final bz2Input = InputFileStream(archivePath);
    final tarOutput = OutputFileStream(tempTarPath);
    try {
      BZip2Decoder().decodeStream(bz2Input, tarOutput, verify: true);
    } finally {
      tarOutput.closeSync();
      bz2Input.closeSync();
    }

    final tarInput = InputFileStream(tempTarPath);
    try {
      TarDecoder().decodeStream(
        tarInput,
        verify: true,
        keepEntries: false,
        callback: (entry) {
          if (!entry.isFile || entry.isSymbolicLink) {
            return;
          }

          final normalized = entry.name.replaceAll('\\', '/');
          final segments = normalized.split('/');
          if (segments.contains('espeak-ng-data')) {
            return;
          }

          final fileName = p.basename(normalized);
          if (!_requiredModelFileNames.contains(fileName)) {
            return;
          }

          final outPath = p.join(stagingDirPath, fileName);
          final outStream = OutputFileStream(outPath);
          try {
            entry.writeContent(outStream);
          } finally {
            outStream.closeSync();
          }
        },
      );
    } finally {
      tarInput.closeSync();
    }

    final missingOrEmpty = <String>[];
    for (final fileName in _requiredModelFileNames) {
      final extractedFile = File(p.join(stagingDirPath, fileName));
      if (!extractedFile.existsSync() || extractedFile.lengthSync() <= 0) {
        missingOrEmpty.add(fileName);
      }
    }
    if (missingOrEmpty.isNotEmpty) {
      throw StateError(
        'Extracted KittenTTS archive is missing or has empty required files: '
        '${missingOrEmpty.join(', ')}',
      );
    }
  } finally {
    if (tempTarFile.existsSync()) {
      try {
        tempTarFile.deleteSync();
      } catch (_) {}
    }
  }
}
