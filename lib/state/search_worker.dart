import 'dart:async';
import 'dart:isolate';

import '../data/models.dart';
import '../data/taxonomy_database.dart';

/// Persistent background isolate for non-blocking SQLite fuzzy search.
class SearchWorker {
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  final Map<int, Completer<List<SearchResult>>> _pending = {};
  int _nextRequestId = 1;
  bool _isClosing = false;

  bool get isRunning => _commandPort != null && !_isClosing;

  Future<void> start(String dbPath) async {
    await close();
    _isClosing = false;

    final readyCompleter = Completer<SendPort>();
    final responsePort = ReceivePort();
    _responsePort = responsePort;

    responsePort.listen((message) {
      if (message is SendPort) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message);
        }
        return;
      }
      if (message is Map) {
        final type = message['type'];
        if (type == 'closed') {
          responsePort.close();
          return;
        }
        final id = message['id'] as int?;
        if (id == null) return;
        final completer = _pending.remove(id);
        if (completer == null || completer.isCompleted) return;

        if (type == 'result') {
          final raw = (message['results'] as List).cast<List<Object?>>();
          final results = raw
              .map(
                (r) => SearchResult(
                  taxId: r[0] as int,
                  matchedName: r[1] as String,
                  nameClass: r[2] as String,
                  scientificName: r[3] as String,
                  rank: r[4] as String,
                  score: r[5] as double,
                ),
              )
              .toList();
          completer.complete(results);
        } else if (type == 'error') {
          completer.completeError(StateError(message['error'] as String));
        }
      }
    });

    _isolate = await Isolate.spawn<_WorkerInit>(
      _searchWorkerMain,
      _WorkerInit(dbPath: dbPath, replyPort: responsePort.sendPort),
    );
    _commandPort = await readyCompleter.future;
  }

  Future<List<SearchResult>> search({
    required String query,
    required NameFilter filter,
    required bool hideNonSpecific,
    required bool hideSubspecies,
    int limit = 40,
  }) {
    final port = _commandPort;
    if (port == null || _isClosing) {
      return Future.value(const []);
    }
    final id = _nextRequestId++;
    final completer = Completer<List<SearchResult>>();
    _pending[id] = completer;

    port.send({
      'type': 'search',
      'id': id,
      'query': query,
      'filter': filter.index,
      'hideNonSpecific': hideNonSpecific,
      'hideSubspecies': hideSubspecies,
      'limit': limit,
    });
    return completer.future;
  }

  Future<void> close() async {
    _isClosing = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const []);
    }
    _pending.clear();

    final port = _commandPort;
    _commandPort = null;
    if (port != null) {
      final done = Completer<void>();
      final ackPort = ReceivePort();
      ackPort.listen((_) {
        if (!done.isCompleted) done.complete();
        ackPort.close();
      });
      port.send({'type': 'close', 'ack': ackPort.sendPort});
      await done.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => ackPort.close(),
      );
    }

    _responsePort?.close();
    _responsePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

class _WorkerInit {
  const _WorkerInit({required this.dbPath, required this.replyPort});

  final String dbPath;
  final SendPort replyPort;
}

void _searchWorkerMain(_WorkerInit init) {
  final commandPort = ReceivePort();
  TaxonomyRepository? repo;
  try {
    repo = TaxonomyRepository.openReadOnly(init.dbPath);
  } catch (_) {
    repo = null;
  }

  init.replyPort.send(commandPort.sendPort);

  commandPort.listen((message) {
    if (message is! Map) return;
    final type = message['type'];

    if (type == 'close') {
      repo?.close();
      repo = null;
      commandPort.close();
      final ack = message['ack'] as SendPort?;
      ack?.send(true);
      init.replyPort.send({'type': 'closed'});
      return;
    }

    if (type == 'search') {
      final id = message['id'] as int;
      try {
        final r = repo;
        if (r == null) {
          init.replyPort.send({'type': 'result', 'id': id, 'results': const []});
          return;
        }
        final results = r.fuzzySearch(
          message['query'] as String,
          filter: NameFilter.values[message['filter'] as int],
          hideNonSpecific: message['hideNonSpecific'] as bool,
          hideSubspecies: message['hideSubspecies'] as bool,
          limit: message['limit'] as int,
        );
        init.replyPort.send({
          'type': 'result',
          'id': id,
          'results': results
              .map(
                (x) => <Object?>[
                  x.taxId,
                  x.matchedName,
                  x.nameClass,
                  x.scientificName,
                  x.rank,
                  x.score,
                ],
              )
              .toList(),
        });
      } catch (e) {
        init.replyPort.send({
          'type': 'error',
          'id': id,
          'error': '$e',
        });
      }
    }
  });
}
