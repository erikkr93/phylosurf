import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ncbi_taxonomy_explorer/services/kitten_model_manager.dart';
import 'package:path/path.dart' as p;

Uint8List _buildTestArchive({
  required List<int> modelBytes,
  required List<int> voicesBytes,
  required String tokensContent,
  List<int>? espeakBytes,
}) {
  final archive = Archive()
    ..add(
      ArchiveFile.bytes(
        '${KittenModelManager.modelId}/${KittenModelManager.modelFileName}',
        modelBytes,
      ),
    )
    ..add(
      ArchiveFile.bytes(
        '${KittenModelManager.modelId}/${KittenModelManager.voicesFileName}',
        voicesBytes,
      ),
    )
    ..add(
      ArchiveFile.string(
        '${KittenModelManager.modelId}/${KittenModelManager.tokensFileName}',
        tokensContent,
      ),
    );

  if (espeakBytes != null) {
    archive.add(
      ArchiveFile.bytes(
        '${KittenModelManager.modelId}/espeak-ng-data/en_dict',
        espeakBytes,
      ),
    );
  }

  final tarBytes = TarEncoder().encodeBytes(archive);
  return BZip2Encoder().encodeBytes(tarBytes);
}

class _FakeArchiveClient extends http.BaseClient {
  _FakeArchiveClient({
    required this.statusCode,
    required this.bodyBytes,
    this.chunkSize = 64,
    this.onSend,
  });

  final int statusCode;
  final List<int> bodyBytes;
  final int chunkSize;
  final Future<void> Function()? onSend;

  int requestCount = 0;
  final List<Uri> requestedUris = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    requestedUris.add(request.url);
    if (onSend != null) {
      await onSend!();
    }

    Stream<List<int>> chunkedStream() async* {
      for (var offset = 0; offset < bodyBytes.length; offset += chunkSize) {
        final end = offset + chunkSize < bodyBytes.length
            ? offset + chunkSize
            : bodyBytes.length;
        yield bodyBytes.sublist(offset, end);
      }
    }

    return http.StreamedResponse(
      chunkedStream(),
      statusCode,
      contentLength: bodyBytes.length,
      request: request,
    );
  }
}

void main() {
  late Directory tempDir;
  final testUri = Uri.parse('https://example.test/kitten-nano.tar.bz2');
  final modelBytes = List<int>.generate(256, (i) => i % 251);
  final voicesBytes = List<int>.generate(128, (i) => (i * 7) % 256);
  const tokensContent = 'a 1\nb 2\nc 3\n';
  final espeakBytes = List<int>.filled(64, 42);
  late Uint8List validArchiveBytes;

  setUpAll(() {
    validArchiveBytes = _buildTestArchive(
      modelBytes: modelBytes,
      voicesBytes: voicesBytes,
      tokensContent: tokensContent,
      espeakBytes: espeakBytes,
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kitten_model_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'downloads and extracts required files, skips espeak-ng-data, cleans temp files, and reports progress',
    () async {
      final client = _FakeArchiveClient(
        statusCode: 200,
        bodyBytes: validArchiveBytes,
        chunkSize: 32,
      );
      final manager = KittenModelManager(
        client: client,
        baseDirProvider: () async => tempDir,
        downloadUri: testUri,
      );
      addTearDown(manager.dispose);

      expect(await manager.getReadyModelPaths(), isNull);

      final progressEvents = <KittenModelProgress>[];
      final paths = await manager.ensureModelReady(
        onProgress: progressEvents.add,
      );

      expect(client.requestCount, 1);
      expect(client.requestedUris, [testUri]);

      expect(
        paths.directory,
        p.join(tempDir.path, 'tts_models', KittenModelManager.modelId),
      );
      expect(File(paths.modelPath).readAsBytesSync(), modelBytes);
      expect(File(paths.voicesPath).readAsBytesSync(), voicesBytes);
      expect(File(paths.tokensPath).readAsStringSync(), tokensContent);

      // espeak-ng-data and all non-required entries must be skipped.
      expect(
        Directory(p.join(paths.directory, 'espeak-ng-data')).existsSync(),
        isFalse,
      );
      expect(File(p.join(paths.directory, 'en_dict')).existsSync(), isFalse);
      final extractedEntries = Directory(paths.directory)
          .listSync()
          .map((e) => p.basename(e.path))
          .toSet();
      expect(extractedEntries, {
        KittenModelManager.modelFileName,
        KittenModelManager.voicesFileName,
        KittenModelManager.tokensFileName,
      });

      // Part and staging artifacts must be cleaned up.
      final modelsRoot = Directory(p.join(tempDir.path, 'tts_models'));
      expect(
        File(
          p.join(modelsRoot.path, '${KittenModelManager.modelId}.tar.bz2.part'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(modelsRoot.path, '${KittenModelManager.modelId}.tar.part'),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(modelsRoot.path, '${KittenModelManager.modelId}.staging'),
        ).existsSync(),
        isFalse,
      );

      // Verify progress stages and fractions.
      final stages = progressEvents.map((e) => e.stage).toList();
      expect(stages, contains(KittenModelStage.downloading));
      expect(stages, contains(KittenModelStage.extracting));
      expect(stages.last, KittenModelStage.ready);
      expect(progressEvents.last.fraction, 1.0);

      final downloadFractions = progressEvents
          .where(
            (e) => e.stage == KittenModelStage.downloading && e.fraction != null,
          )
          .map((e) => e.fraction!)
          .toList();
      expect(downloadFractions, isNotEmpty);
      expect(downloadFractions.every((f) => f >= 0.0 && f <= 0.85), isTrue);
      expect(downloadFractions.last, closeTo(0.85, 1e-6));
    },
  );

  test(
    'subsequent getReadyModelPaths and ensureModelReady use cache without HTTP calls',
    () async {
      final client = _FakeArchiveClient(
        statusCode: 200,
        bodyBytes: validArchiveBytes,
      );
      final manager = KittenModelManager(
        client: client,
        baseDirProvider: () async => tempDir,
        downloadUri: testUri,
      );
      addTearDown(manager.dispose);

      final initialPaths = await manager.ensureModelReady();
      expect(client.requestCount, 1);

      final readyPaths = await manager.getReadyModelPaths();
      expect(readyPaths, isNotNull);
      expect(readyPaths!.directory, initialPaths.directory);
      expect(readyPaths.modelPath, initialPaths.modelPath);
      expect(readyPaths.voicesPath, initialPaths.voicesPath);
      expect(readyPaths.tokensPath, initialPaths.tokensPath);
      expect(client.requestCount, 1);

      final cachedProgress = <KittenModelProgress>[];
      final cachedPaths = await manager.ensureModelReady(
        onProgress: cachedProgress.add,
      );
      expect(cachedPaths.directory, initialPaths.directory);
      expect(client.requestCount, 1);
      expect(cachedProgress.last.stage, KittenModelStage.ready);
      expect(cachedProgress.last.fraction, 1.0);
    },
  );

  test(
    'concurrent ensureModelReady calls share a single HTTP download',
    () async {
      final requestStarted = Completer<void>();
      final releaseDownload = Completer<void>();
      final client = _FakeArchiveClient(
        statusCode: 200,
        bodyBytes: validArchiveBytes,
        chunkSize: 32,
        onSend: () async {
          if (!requestStarted.isCompleted) {
            requestStarted.complete();
          }
          await releaseDownload.future;
        },
      );
      final manager = KittenModelManager(
        client: client,
        baseDirProvider: () async => tempDir,
        downloadUri: testUri,
      );
      addTearDown(manager.dispose);

      final progressA = <KittenModelProgress>[];
      final progressB = <KittenModelProgress>[];
      final progressC = <KittenModelProgress>[];

      // Start two callers synchronously, then attach a third while in flight.
      final futureA = manager.ensureModelReady(onProgress: progressA.add);
      final futureB = manager.ensureModelReady(onProgress: progressB.add);

      await requestStarted.future;
      final futureC = manager.ensureModelReady(onProgress: progressC.add);
      releaseDownload.complete();

      final results = await Future.wait([futureA, futureB, futureC]);

      expect(client.requestCount, 1);
      expect(results[0].directory, results[1].directory);
      expect(results[0].directory, results[2].directory);
      expect(results[0].modelPath, results[1].modelPath);
      expect(results[0].voicesPath, results[2].voicesPath);
      expect(results[0].tokensPath, results[2].tokensPath);

      for (final events in [progressA, progressB, progressC]) {
        final stages = events.map((e) => e.stage).toList();
        expect(stages, contains(KittenModelStage.downloading));
        expect(stages, contains(KittenModelStage.extracting));
        expect(stages.last, KittenModelStage.ready);
      }
    },
  );

  test(
    'non-200 HTTP response throws cleanly and leaves no corrupt ready directory',
    () async {
      final client = _FakeArchiveClient(
        statusCode: 404,
        bodyBytes: 'Not Found'.codeUnits,
      );
      final manager = KittenModelManager(
        client: client,
        baseDirProvider: () async => tempDir,
        downloadUri: testUri,
      );
      addTearDown(manager.dispose);

      await expectLater(
        manager.ensureModelReady(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('404'),
          ),
        ),
      );

      expect(await manager.getReadyModelPaths(), isNull);

      final modelsRoot = Directory(p.join(tempDir.path, 'tts_models'));
      expect(
        Directory(
          p.join(modelsRoot.path, KittenModelManager.modelId),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(modelsRoot.path, '${KittenModelManager.modelId}.staging'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(modelsRoot.path, '${KittenModelManager.modelId}.tar.bz2.part'),
        ).existsSync(),
        isFalse,
      );
    },
  );
}
