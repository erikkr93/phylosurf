import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../data/ncbi_sync_service.dart';
import '../data/taxon_filter.dart';
import '../data/taxonomy_database.dart';
import 'search_worker.dart';

class TaxonomyController extends ChangeNotifier {
  TaxonomyController({
    TaxonomyRepository? repository,
    NcbiSyncService? syncService,
  })  : _repo = repository,
        _syncService = syncService ?? NcbiSyncService();

  TaxonomyRepository? _repo;
  final NcbiSyncService _syncService;
  final SearchWorker _searchWorker = SearchWorker();

  DatabaseStatus? _status;
  bool _isInitializing = true;
  bool _isSyncing = false;
  bool _isSearching = false;
  bool _isDisposed = false;
  int _searchSeq = 0;
  IngestProgress? _syncProgress;
  String? _syncError;

  String _query = '';
  NameFilter _filter = NameFilter.all;
  bool _hideNonSpecific = true;
  bool _hideSubspecies = true;
  List<SearchResult> _searchResults = const [];
  Timer? _searchDebounce;

  final Map<int, TaxonNode> _nodeCache = {};
  final Map<int, List<TaxonNode>> _childrenCache = {};
  final Set<int> _expandedIds = {};
  final List<int> _history = [];
  int _historyIndex = -1;
  int? _selectedTaxId;
  TaxonDetails? _selectedDetails;

  DatabaseStatus? get status => _status;
  bool get isInitializing => _isInitializing;
  bool get isSyncing => _isSyncing;
  bool get isSearching => _isSearching;
  IngestProgress? get syncProgress => _syncProgress;
  String? get syncError => _syncError;
  bool get hasDatabase => (_status?.exists ?? false) && (_status?.nodeCount ?? 0) > 0;

  String get query => _query;
  NameFilter get filter => _filter;
  bool get hideNonSpecific => _hideNonSpecific;
  bool get hideSubspecies => _hideSubspecies;
  List<SearchResult> get searchResults => _searchResults;

  bool canExpandNode(TaxonNode taxon) {
    if (taxon.childCount <= 0) return false;
    if (_hideSubspecies) {
      final rank = taxon.rank.trim().toLowerCase();
      if (rank == 'species' || isInfraspecificRank(rank)) return false;
    }
    return true;
  }

  Map<int, TaxonNode> get nodeCache => _nodeCache;
  Map<int, List<TaxonNode>> get childrenCache => _childrenCache;
  Set<int> get expandedIds => _expandedIds;
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward =>
      _historyIndex >= 0 && _historyIndex < _history.length - 1;
  int? get selectedTaxId => _selectedTaxId;
  TaxonDetails? get selectedDetails => _selectedDetails;

  Future<void> init() async {
    _isInitializing = true;
    notifyListeners();

    try {
      if (_repo != null) {
        _status = _repo!.getStatus();
        _loadInitialTree();
        return;
      }

      final dir = await getApplicationSupportDirectory();
      final dbPath = p.join(dir.path, 'taxonomy.db');
      if (File(dbPath).existsSync()) {
        _repo = TaxonomyRepository.openFile(dbPath);
        _status = _repo!.getStatus();
        _loadInitialTree();
        await _searchWorker.start(dbPath);
      } else {
        _status = DatabaseStatus(exists: false, dbPath: dbPath);
      }
    } catch (e) {
      _syncError = 'Failed to open local database: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _loadInitialTree() {
    final repo = _repo;
    if (repo == null) return;

    _nodeCache.clear();
    _childrenCache.clear();
    _expandedIds.clear();

    final root = repo.getNode(1);
    if (root == null) return;

    _nodeCache[1] = root;
    _expandedIds.add(1);
    final rootChildren = repo.getChildren(
      1,
      hideNonSpecific: _hideNonSpecific,
      hideSubspecies: _hideSubspecies,
    );
    _childrenCache[1] = rootChildren;
    for (final c in rootChildren) {
      _nodeCache[c.taxId] = c;
    }

    _selectedTaxId = 1;
    _selectedDetails = repo.getTaxonDetails(
      1,
      hideNonSpecific: _hideNonSpecific,
      hideSubspecies: _hideSubspecies,
    );
    _history
      ..clear()
      ..add(1);
    _historyIndex = 0;
  }

  void setQuery(String value) {
    _query = value;
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      _searchSeq++;
      _isSearching = false;
      _searchResults = const [];
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    _searchDebounce = Timer(const Duration(milliseconds: 180), _runSearch);
  }

  void setFilter(NameFilter value) {
    if (_filter == value) return;
    _filter = value;
    if (_query.trim().isNotEmpty) {
      _runSearch();
    } else {
      notifyListeners();
    }
  }

  void setHideNonSpecific(bool value) {
    if (_hideNonSpecific == value) return;
    _hideNonSpecific = value;
    _refreshActiveFilters();
  }

  void setHideSubspecies(bool value) {
    if (_hideSubspecies == value) return;
    _hideSubspecies = value;
    _refreshActiveFilters();
  }

  void _refreshActiveFilters() {
    final repo = _repo;
    if (repo != null) {
      _childrenCache.clear();
      for (final expandedId in _expandedIds) {
        final children = repo.getChildren(
          expandedId,
          hideNonSpecific: _hideNonSpecific,
          hideSubspecies: _hideSubspecies,
        );
        _childrenCache[expandedId] = children;
        for (final c in children) {
          _nodeCache[c.taxId] = c;
        }
      }
      if (_selectedTaxId != null) {
        _selectedDetails = repo.getTaxonDetails(
          _selectedTaxId!,
          hideNonSpecific: _hideNonSpecific,
          hideSubspecies: _hideSubspecies,
        );
      }
      if (_query.trim().isNotEmpty) {
        _runSearch();
        return;
      }
    }
    notifyListeners();
  }

  Future<void> _runSearch() async {
    final repo = _repo;
    final q = _query.trim();
    final seq = ++_searchSeq;
    if (repo == null || q.isEmpty) {
      _isSearching = false;
      _searchResults = const [];
      notifyListeners();
      return;
    }

    if (_searchWorker.isRunning) {
      _isSearching = true;
      notifyListeners();
      try {
        final results = await _searchWorker.search(
          query: q,
          filter: _filter,
          hideNonSpecific: _hideNonSpecific,
          hideSubspecies: _hideSubspecies,
          limit: 40,
        );
        if (_isDisposed || seq != _searchSeq) return;
        _searchResults = results;
      } catch (_) {
        if (_isDisposed || seq != _searchSeq) return;
      } finally {
        if (!_isDisposed && seq == _searchSeq) {
          _isSearching = false;
          notifyListeners();
        }
      }
      return;
    }

    // Fallback for in-memory repositories (e.g. unit/widget tests).
    _searchResults = repo.fuzzySearch(
      q,
      filter: _filter,
      hideNonSpecific: _hideNonSpecific,
      hideSubspecies: _hideSubspecies,
      limit: 40,
    );
    _isSearching = false;
    notifyListeners();
  }

  void toggleExpanded(int taxId) {
    final repo = _repo;
    if (repo == null) return;

    if (_expandedIds.contains(taxId)) {
      _expandedIds.remove(taxId);
      notifyListeners();
      return;
    }

    final node = _nodeCache[taxId] ?? repo.getNode(taxId);
    if (node != null && !canExpandNode(node)) return;

    _expandedIds.add(taxId);
    if (!_childrenCache.containsKey(taxId)) {
      final children = repo.getChildren(
        taxId,
        hideNonSpecific: _hideNonSpecific,
        hideSubspecies: _hideSubspecies,
      );
      _childrenCache[taxId] = children;
      for (final c in children) {
        _nodeCache[c.taxId] = c;
      }
    }
    notifyListeners();
  }

  void _pushHistory(int taxId) {
    if (_historyIndex >= 0 && _history[_historyIndex] == taxId) return;
    if (_historyIndex + 1 < _history.length) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(taxId);
    _historyIndex = _history.length - 1;
  }

  int? goBack() {
    if (!canGoBack) return null;
    _historyIndex--;
    final taxId = _history[_historyIndex];
    _revealTaxonInternal(taxId, recordHistory: false, clearSearch: false);
    return taxId;
  }

  int? goForward() {
    if (!canGoForward) return null;
    _historyIndex++;
    final taxId = _history[_historyIndex];
    _revealTaxonInternal(taxId, recordHistory: false, clearSearch: false);
    return taxId;
  }

  void selectTaxon(int taxId) {
    final repo = _repo;
    if (repo == null) return;
    _selectedTaxId = taxId;
    _selectedDetails = repo.getTaxonDetails(
      taxId,
      hideNonSpecific: _hideNonSpecific,
      hideSubspecies: _hideSubspecies,
    );
    _pushHistory(taxId);
    notifyListeners();
  }

  void revealTaxon(int taxId) {
    _revealTaxonInternal(taxId, recordHistory: true, clearSearch: true);
  }

  void _revealTaxonInternal(
    int taxId, {
    required bool recordHistory,
    required bool clearSearch,
  }) {
    final repo = _repo;
    if (repo == null) return;

    final lineage = repo.getLineage(taxId);
    for (final ancestor in lineage) {
      _nodeCache[ancestor.taxId] = ancestor;
      if (ancestor.taxId != taxId && canExpandNode(ancestor)) {
        _expandedIds.add(ancestor.taxId);
        if (!_childrenCache.containsKey(ancestor.taxId)) {
          final children = repo.getChildren(
            ancestor.taxId,
            hideNonSpecific: _hideNonSpecific,
            hideSubspecies: _hideSubspecies,
          );
          _childrenCache[ancestor.taxId] = children;
          for (final c in children) {
            _nodeCache[c.taxId] = c;
          }
        }
      }
    }

    _selectedTaxId = taxId;
    _selectedDetails = repo.getTaxonDetails(
      taxId,
      hideNonSpecific: _hideNonSpecific,
      hideSubspecies: _hideSubspecies,
    );
    if (recordHistory) {
      _pushHistory(taxId);
    }
    if (clearSearch) {
      _query = '';
      _searchResults = const [];
    }
    notifyListeners();
  }

  Future<void> syncFromNcbi({
    bool force = false,
    bool compactImport = false,
  }) async {
    if (_isSyncing) return;
    final dbPath = _status?.dbPath;
    if (dbPath == null || dbPath.isEmpty) return;

    _isSyncing = true;
    _syncError = null;
    _syncProgress = const IngestProgress(
      stage: IngestStage.checking,
      message: 'Checking NCBI for updates...',
    );
    notifyListeners();

    try {
      final check = await _syncService.checkForUpdate(
        _status ?? DatabaseStatus(exists: false, dbPath: dbPath),
      );

      if (!force && !check.updateAvailable && hasDatabase) {
        _syncProgress = const IngestProgress(
          stage: IngestStage.done,
          message: 'Your taxonomy database is already up to date.',
          fraction: 1.0,
        );
        return;
      }

      await _syncService.downloadAndBuildDatabase(
        dbPath: dbPath,
        compactImport: compactImport,
        etag: check.etag,
        lastModified: check.lastModified,
        onProgress: (p) {
          _syncProgress = p;
          notifyListeners();
        },
        onBeforeSwap: () async {
          await _searchWorker.close();
          _repo?.close();
          _repo = null;
        },
      );

      _repo = TaxonomyRepository.openFile(dbPath);
      _status = _repo!.getStatus();
      _loadInitialTree();
      await _searchWorker.start(dbPath);
    } catch (e) {
      _syncError = '$e';
      if (_repo == null && File(dbPath).existsSync()) {
        _repo = TaxonomyRepository.openFile(dbPath);
        _status = _repo!.getStatus();
        await _searchWorker.start(dbPath);
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchDebounce?.cancel();
    _searchWorker.close();
    _repo?.close();
    _syncService.dispose();
    super.dispose();
  }
}
