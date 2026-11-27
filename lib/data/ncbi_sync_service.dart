import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'taxonomy_database.dart';

const String defaultNcbiTaxdumpUrl =
    'https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/new_taxdump.tar.gz';

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    this.etag,
    this.lastModified,
    this.contentLength,
  });

  final bool updateAvailable;
  final String? etag;
  final String? lastModified;
  final int? contentLength;
}

class NcbiSyncService {
  NcbiSyncService({
    this.taxdumpUrl = defaultNcbiTaxdumpUrl,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  final String taxdumpUrl;
  final http.Client _client;

  void dispose() => _client.close();

  Future<UpdateCheckResult> checkForUpdate(DatabaseStatus current) async {
    final res = await _client.head(Uri.parse(taxdumpUrl));
    if (res.statusCode < 200 || res.statusCode >= 400) {
      throw HttpException(
        'HTTP ${res.statusCode} checking NCBI taxonomy update',
        uri: Uri.parse(taxdumpUrl),
      );
    }

    final remoteEtag = res.headers['etag'];
    final remoteLastMod = res.headers['last-modified'];
    final contentLength = int.tryParse(res.headers['content-length'] ?? '');

    var updateAvailable = !current.exists || current.nodeCount == 0;
    if (!updateAvailable) {
      if (remoteEtag != null && current.etag != null) {
        updateAvailable = remoteEtag != current.etag;
      } else if (remoteLastMod != null && current.lastModified != null) {
        updateAvailable = remoteLastMod != current.lastModified;
      } else {
        updateAvailable = true;
      }
    }

    return UpdateCheckResult(
      updateAvailable: updateAvailable,
      etag: remoteEtag,
      lastModified: remoteLastMod,
      contentLength: contentLength,
    );
  }

  /// Downloads `new_taxdump.tar.gz`, extracts `nodes.dmp` and `names.dmp`
  /// in a background isolate, builds `taxonomy_staging.db`, and atomically
  /// swaps it into [dbPath].
  Future<({int nodeCount, int nameCount})> downloadAndBuildDatabase({
    required String dbPath,
    required void Function(IngestProgress progress) onProgress,
    Future<void> Function()? onBeforeSwap,
    bool compactImport = false,
    String? etag,
    String? lastModified,
  }) async {
    final dbDir = Directory(p.dirname(dbPath));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    final workDir = await Directory.systemTemp.createTemp('ncbi_taxdump_');
    final tarGzFile = File(p.join(workDir.path, 'new_taxdump.tar.gz'));
    final stagingDbPath = '$dbPath.staging';

    try {
      onProgress(
        const IngestProgress(
          stage: IngestStage.downloading,
          message: 'Connecting to NCBI...',
          fraction: 0,
        ),
      );

      final request = http.Request('GET', Uri.parse(taxdumpUrl));
      final response = await _client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to download taxdump (HTTP ${response.statusCode})',
          uri: Uri.parse(taxdumpUrl),
        );
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final sink = tarGzFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final mb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final fraction =
              totalBytes != null && totalBytes > 0 ? receivedBytes / totalBytes : null;
          final totalMb = totalBytes != null
              ? '/ ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '';
          onProgress(
            IngestProgress(
              stage: IngestStage.downloading,
              message: 'Downloading new_taxdump.tar.gz ($mb $totalMb)...',
              fraction: fraction,
            ),
          );
        }
      } finally {
        await sink.close();
      }

      final metadata = <String, String>{
        'etag': ?etag,
        'last_modified': ?lastModified,
      };

      final result = await _runBuildInIsolate(
        tarGzPath: tarGzFile.path,
        workDirPath: workDir.path,
        stagingDbPath: stagingDbPath,
        compactImport: compactImport,
        metadata: metadata,
        onProgress: onProgress,
      );

      await onBeforeSwap?.call();

      final targetFile = File(dbPath);
      final stagingFile = File(stagingDbPath);
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }
      await stagingFile.rename(dbPath);

      onProgress(
        IngestProgress(
          stage: IngestStage.done,
          message:
              'Database ready (${result.nodeCount} taxa, ${result.nameCount} names).',
          fraction: 1.0,
        ),
      );

      return result;
    } finally {
      if (File(stagingDbPath).existsSync()) {
        try {
          File(stagingDbPath).deleteSync();
        } catch (_) {}
      }
      if (workDir.existsSync()) {
        try {
          workDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }
}

Future<({int nodeCount, int nameCount})> _runBuildInIsolate({
  required String tarGzPath,
  required String workDirPath,
  required String stagingDbPath,
  required bool compactImport,
  required Map<String, String> metadata,
  required void Function(IngestProgress progress) onProgress,
}) async {
  final receivePort = ReceivePort();
  final completer = Completer<({int nodeCount, int nameCount})>();

  receivePort.listen((message) {
    if (message is IngestProgress) {
      onProgress(message);
    } else if (message is Map && message['type'] == 'done') {
      completer.complete((
        nodeCount: message['nodeCount'] as int,
        nameCount: message['nameCount'] as int,
      ));
      receivePort.close();
    } else if (message is Map && message['type'] == 'error') {
      completer.completeError(
        StateError(message['error'] as String),
      );
      receivePort.close();
    }
  });

  await Isolate.spawn<_IsolateArgs>(
    _buildDatabaseIsolateMain,
    _IsolateArgs(
      sendPort: receivePort.sendPort,
      tarGzPath: tarGzPath,
      workDirPath: workDirPath,
      stagingDbPath: stagingDbPath,
      compactImport: compactImport,
      metadata: metadata,
    ),
  );

  return completer.future;
}

class _IsolateArgs {
  const _IsolateArgs({
    required this.sendPort,
    required this.tarGzPath,
    required this.workDirPath,
    required this.stagingDbPath,
    required this.compactImport,
    required this.metadata,
  });

  final SendPort sendPort;
  final String tarGzPath;
  final String workDirPath;
  final String stagingDbPath;
  final bool compactImport;
  final Map<String, String> metadata;
}

Future<void> _buildDatabaseIsolateMain(_IsolateArgs args) async {
  try {
    args.sendPort.send(
      const IngestProgress(
        stage: IngestStage.extracting,
        message: 'Extracting nodes.dmp & names.dmp...',
      ),
    );

    final extracted = await extractDmpFilesFromTarGz(
      tarGzFile: File(args.tarGzPath),
      outputDir: Directory(args.workDirPath),
      targetNames: const {'nodes.dmp', 'names.dmp'},
    );

    final nodesFile = extracted['nodes.dmp'];
    final namesFile = extracted['names.dmp'];
    if (nodesFile == null || namesFile == null) {
      throw StateError('Archive did not contain nodes.dmp and names.dmp');
    }

    if (File(args.stagingDbPath).existsSync()) {
      File(args.stagingDbPath).deleteSync();
    }

    final db = sqlite3.open(args.stagingDbPath);
    try {
      final counts = await TaxonomyRepository.populateFromFiles(
        db: db,
        nodesFile: nodesFile,
        namesFile: namesFile,
        compactImport: args.compactImport,
        metadata: args.metadata,
        onProgress: (p) => args.sendPort.send(p),
      );
      args.sendPort.send({
        'type': 'done',
        'nodeCount': counts.nodeCount,
        'nameCount': counts.nameCount,
      });
    } finally {
      db.close();
    }
  } catch (e, st) {
    args.sendPort.send({
      'type': 'error',
      'error': '$e\n$st',
    });
  }
}

/// Streams a `.tar.gz` archive and writes only files whose basename is in
/// [targetNames] into [outputDir], using constant memory.
Future<Map<String, File>> extractDmpFilesFromTarGz({
  required File tarGzFile,
  required Directory outputDir,
  required Set<String> targetNames,
}) async {
  final found = <String, File>{};
  final headerBuf = BytesBuilder(copy: false);

  String? currentName;
  int remainingBytes = 0;
  int paddingBytes = 0;
  IOSink? currentSink;

  Future<void> closeCurrentSink() async {
    if (currentSink != null) {
      await currentSink!.flush();
      await currentSink!.close();
      currentSink = null;
    }
  }

  final stream = tarGzFile.openRead().transform(gzip.decoder);
  await for (final rawChunk in stream) {
    final chunk = rawChunk is Uint8List ? rawChunk : Uint8List.fromList(rawChunk);
    var offset = 0;

    while (offset < chunk.length) {
      if (remainingBytes > 0) {
        final toTake = remainingBytes < (chunk.length - offset)
            ? remainingBytes
            : (chunk.length - offset);
        if (currentSink != null) {
          currentSink!.add(Uint8List.sublistView(chunk, offset, offset + toTake));
        }
        offset += toTake;
        remainingBytes -= toTake;
        if (remainingBytes == 0) {
          await closeCurrentSink();
          if (found.length == targetNames.length) {
            return found;
          }
        }
        continue;
      }

      if (paddingBytes > 0) {
        final toSkip = paddingBytes < (chunk.length - offset)
            ? paddingBytes
            : (chunk.length - offset);
        offset += toSkip;
        paddingBytes -= toSkip;
        continue;
      }

      final needed = 512 - headerBuf.length;
      final available = chunk.length - offset;
      final toCopy = needed < available ? needed : available;
      headerBuf.add(Uint8List.sublistView(chunk, offset, offset + toCopy));
      offset += toCopy;

      if (headerBuf.length == 512) {
        final header = headerBuf.takeBytes();
        if (_isZeroBlock(header)) {
          continue;
        }

        final rawName = _readCString(header, 0, 100);
        final baseName = p.basename(rawName);
        final size = _parseOctal(header, 124, 12);
        final typeFlag = header[156];
        final isRegularFile = typeFlag == 0 || typeFlag == 48; // '\0' or '0'

        remainingBytes = size;
        paddingBytes = (512 - (size % 512)) % 512;
        currentName = baseName;

        if (isRegularFile && targetNames.contains(currentName) && size > 0) {
          final outFile = File(p.join(outputDir.path, currentName));
          currentSink = outFile.openWrite();
          found[currentName] = outFile;
        }
      }
    }
  }

  await closeCurrentSink();
  return found;
}

bool _isZeroBlock(Uint8List block) {
  for (final b in block) {
    if (b != 0) return false;
  }
  return true;
}

String _readCString(Uint8List bytes, int start, int length) {
  var end = start;
  final limit = start + length;
  while (end < limit && bytes[end] != 0) {
    end++;
  }
  return String.fromCharCodes(bytes, start, end);
}

int _parseOctal(Uint8List bytes, int start, int length) {
  final str = _readCString(bytes, start, length).trim();
  if (str.isEmpty) return 0;
  return int.tryParse(str, radix: 8) ?? 0;
}
