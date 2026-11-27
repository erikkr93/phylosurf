import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'dmp_parser.dart';
import 'fuzzy_scorer.dart';
import 'models.dart';
import 'taxon_filter.dart';

class TaxonomyRepository {
  TaxonomyRepository(this.db, {this.dbPath = ''});

  final Database db;
  final String dbPath;

  static TaxonomyRepository openFile(String path) {
    final db = sqlite3.open(path);
    return TaxonomyRepository(db, dbPath: path);
  }

  static TaxonomyRepository openReadOnly(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    return TaxonomyRepository(db, dbPath: path);
  }

  static TaxonomyRepository openInMemory() {
    final db = sqlite3.openInMemory();
    return TaxonomyRepository(db);
  }

  void close() => db.close();

  static void createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS nodes (
        tax_id INTEGER PRIMARY KEY,
        parent_tax_id INTEGER NOT NULL,
        rank TEXT NOT NULL,
        scientific_name TEXT NOT NULL DEFAULT '',
        child_count INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS names (
        id INTEGER PRIMARY KEY,
        tax_id INTEGER NOT NULL,
        name_txt TEXT NOT NULL,
        name_class TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS names_fts USING fts5(
        name_txt,
        content='names',
        content_rowid='id',
        tokenize='trigram'
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
  }

  /// Bulk-populates [db] from [nodesLines] and [namesLines] (NCBI .dmp format).
  static ({int nodeCount, int nameCount}) populateFromLines({
    required Database db,
    required Iterable<String> nodesLines,
    required Iterable<String> namesLines,
    bool compactImport = false,
    Map<String, String> metadata = const {},
    void Function(IngestProgress progress)? onProgress,
  }) {
    db.execute('PRAGMA journal_mode = OFF;');
    db.execute('PRAGMA synchronous = OFF;');
    db.execute('PRAGMA temp_store = MEMORY;');

    createSchema(db);

    var nodeCount = 0;
    var nameCount = 0;

    db.execute('BEGIN TRANSACTION;');
    try {
      final insertNode = db.prepare(
        'INSERT OR REPLACE INTO nodes (tax_id, parent_tax_id, rank) VALUES (?, ?, ?);',
      );
      try {
        onProgress?.call(
          const IngestProgress(
            stage: IngestStage.parsingNodes,
            message: 'Parsing nodes.dmp...',
          ),
        );
        for (final line in nodesLines) {
          final parsed = parseNodesLine(line);
          if (parsed == null) continue;
          insertNode.execute([parsed.taxId, parsed.parentTaxId, parsed.rank]);
          nodeCount++;
          if (nodeCount % 250000 == 0) {
            onProgress?.call(
              IngestProgress(
                stage: IngestStage.parsingNodes,
                message: 'Loaded $nodeCount taxa...',
              ),
            );
          }
        }
      } finally {
        insertNode.close();
      }

      final insertName = db.prepare(
        'INSERT INTO names (tax_id, name_txt, name_class) VALUES (?, ?, ?);',
      );
      try {
        onProgress?.call(
          const IngestProgress(
            stage: IngestStage.parsingNames,
            message: 'Parsing names.dmp...',
          ),
        );
        for (final line in namesLines) {
          final parsed = parseNamesLine(line);
          if (parsed == null) continue;
          insertName.execute([parsed.taxId, parsed.nameTxt, parsed.nameClass]);
          nameCount++;
          if (nameCount % 250000 == 0) {
            onProgress?.call(
              IngestProgress(
                stage: IngestStage.parsingNames,
                message: 'Loaded $nameCount names...',
              ),
            );
          }
        }
      } finally {
        insertName.close();
      }

      final counts = _buildIndexesAndMetadata(
        db: db,
        nodeCount: nodeCount,
        nameCount: nameCount,
        compactImport: compactImport,
        metadata: metadata,
        onProgress: onProgress,
      );

      db.execute('COMMIT;');
      nodeCount = counts.nodeCount;
      nameCount = counts.nameCount;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }

    _optimizeAfterPopulate(db, onProgress);

    return (nodeCount: nodeCount, nameCount: nameCount);
  }

  /// Streams [nodesFile] and [namesFile] into [db] with constant memory usage.
  static Future<({int nodeCount, int nameCount})> populateFromFiles({
    required Database db,
    required File nodesFile,
    required File namesFile,
    bool compactImport = false,
    Map<String, String> metadata = const {},
    void Function(IngestProgress progress)? onProgress,
  }) async {
    db.execute('PRAGMA journal_mode = OFF;');
    db.execute('PRAGMA synchronous = OFF;');
    db.execute('PRAGMA temp_store = MEMORY;');

    createSchema(db);

    var nodeCount = 0;
    var nameCount = 0;

    db.execute('BEGIN TRANSACTION;');
    try {
      final insertNode = db.prepare(
        'INSERT OR REPLACE INTO nodes (tax_id, parent_tax_id, rank) VALUES (?, ?, ?);',
      );
      try {
        onProgress?.call(
          const IngestProgress(
            stage: IngestStage.parsingNodes,
            message: 'Parsing nodes.dmp...',
          ),
        );
        final lines = nodesFile
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          final parsed = parseNodesLine(line);
          if (parsed == null) continue;
          insertNode.execute([parsed.taxId, parsed.parentTaxId, parsed.rank]);
          nodeCount++;
          if (nodeCount % 250000 == 0) {
            onProgress?.call(
              IngestProgress(
                stage: IngestStage.parsingNodes,
                message: 'Loaded $nodeCount taxa...',
              ),
            );
          }
        }
      } finally {
        insertNode.close();
      }

      final insertName = db.prepare(
        'INSERT INTO names (tax_id, name_txt, name_class) VALUES (?, ?, ?);',
      );
      try {
        onProgress?.call(
          const IngestProgress(
            stage: IngestStage.parsingNames,
            message: 'Parsing names.dmp...',
          ),
        );
        final lines = namesFile
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          final parsed = parseNamesLine(line);
          if (parsed == null) continue;
          insertName.execute([parsed.taxId, parsed.nameTxt, parsed.nameClass]);
          nameCount++;
          if (nameCount % 250000 == 0) {
            onProgress?.call(
              IngestProgress(
                stage: IngestStage.parsingNames,
                message: 'Loaded $nameCount names...',
              ),
            );
          }
        }
      } finally {
        insertName.close();
      }

      final counts = _buildIndexesAndMetadata(
        db: db,
        nodeCount: nodeCount,
        nameCount: nameCount,
        compactImport: compactImport,
        metadata: metadata,
        onProgress: onProgress,
      );

      db.execute('COMMIT;');
      nodeCount = counts.nodeCount;
      nameCount = counts.nameCount;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }

    _optimizeAfterPopulate(db, onProgress);

    return (nodeCount: nodeCount, nameCount: nameCount);
  }

  static ({int nodeCount, int nameCount}) _buildIndexesAndMetadata({
    required Database db,
    required int nodeCount,
    required int nameCount,
    required bool compactImport,
    required Map<String, String> metadata,
    void Function(IngestProgress progress)? onProgress,
  }) {
    onProgress?.call(
      const IngestProgress(
        stage: IngestStage.indexing,
        message: 'Building indexes & FTS5 trigram search...',
      ),
    );

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_nodes_parent ON nodes(parent_tax_id);
      CREATE INDEX IF NOT EXISTS idx_names_tax_id ON names(tax_id);
    ''');

    db.execute('''
      UPDATE nodes
      SET scientific_name = COALESCE(
        (SELECT n.name_txt FROM names n
         WHERE n.tax_id = nodes.tax_id AND n.name_class = 'scientific name'
         LIMIT 1),
        ''
      );
    ''');

    var finalNodeCount = nodeCount;
    var finalNameCount = nameCount;

    if (compactImport) {
      onProgress?.call(
        const IngestProgress(
          stage: IngestStage.indexing,
          message: 'Pruning non-specific leaf taxa (compact mode)...',
        ),
      );
      final matchExpr = nonSpecificSqlMatchExpr('scientific_name');
      // Iteratively remove non-specific leaf nodes so no specific descendants
      // are ever orphaned.
      while (true) {
        db.execute('''
          CREATE TEMP TABLE IF NOT EXISTS _prune_ids(tax_id INTEGER PRIMARY KEY);
          DELETE FROM _prune_ids;
          INSERT INTO _prune_ids(tax_id)
          SELECT tax_id FROM nodes
          WHERE tax_id != 1
            AND $matchExpr
            AND NOT EXISTS (
              SELECT 1 FROM nodes c
              WHERE c.parent_tax_id = nodes.tax_id AND c.tax_id != nodes.tax_id
            );
        ''');
        final countRow =
            db.select('SELECT COUNT(*) AS cnt FROM _prune_ids;').first;
        if ((countRow['cnt'] as int) == 0) break;

        db.execute(
          'DELETE FROM names WHERE tax_id IN (SELECT tax_id FROM _prune_ids);',
        );
        db.execute(
          'DELETE FROM nodes WHERE tax_id IN (SELECT tax_id FROM _prune_ids);',
        );
      }
      db.execute('DROP TABLE IF EXISTS _prune_ids;');

      finalNodeCount =
          db.select('SELECT COUNT(*) AS cnt FROM nodes;').first['cnt'] as int;
      finalNameCount =
          db.select('SELECT COUNT(*) AS cnt FROM names;').first['cnt'] as int;
    }

    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_names_txt_nocase ON names(name_txt COLLATE NOCASE);',
    );

    db.execute('''
      UPDATE nodes
      SET child_count = COALESCE(
        (SELECT COUNT(*) FROM nodes c
         WHERE c.parent_tax_id = nodes.tax_id AND c.tax_id != nodes.tax_id),
        0
      );
    ''');

    db.execute("INSERT INTO names_fts(names_fts) VALUES('rebuild');");

    final upsertMeta = db.prepare(
      'INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);',
    );
    try {
      final mergedMeta = <String, String>{
        ...metadata,
        'node_count': '$finalNodeCount',
        'name_count': '$finalNameCount',
        'compact_import': '$compactImport',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      for (final entry in mergedMeta.entries) {
        upsertMeta.execute([entry.key, entry.value]);
      }
    } finally {
      upsertMeta.close();
    }

    return (nodeCount: finalNodeCount, nameCount: finalNameCount);
  }

  static void _optimizeAfterPopulate(
    Database db,
    void Function(IngestProgress progress)? onProgress,
  ) {
    onProgress?.call(
      const IngestProgress(
        stage: IngestStage.finalizing,
        message: 'Optimizing database...',
      ),
    );
    db.execute('ANALYZE;');
    db.execute('PRAGMA journal_mode = DELETE;');
    db.execute('PRAGMA synchronous = NORMAL;');
  }

  DatabaseStatus getStatus() {
    final rows = db.select('SELECT key, value FROM metadata;');
    final map = <String, String>{
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
    return DatabaseStatus(
      exists: dbPath.isEmpty ? true : File(dbPath).existsSync(),
      dbPath: dbPath,
      nodeCount: int.tryParse(map['node_count'] ?? '') ?? 0,
      nameCount: int.tryParse(map['name_count'] ?? '') ?? 0,
      etag: map['etag'],
      lastModified: map['last_modified'],
      updatedAt: DateTime.tryParse(map['updated_at'] ?? ''),
    );
  }

  bool hasSpeciesAncestor(int taxId) {
    final rows = db.select(
      '''
      WITH RECURSIVE anc(tax_id, parent_tax_id, rank, depth) AS (
        SELECT tax_id, parent_tax_id, rank, 0
        FROM nodes
        WHERE tax_id = ?
        UNION ALL
        SELECT p.tax_id, p.parent_tax_id, p.rank, anc.depth + 1
        FROM nodes p
        JOIN anc ON p.tax_id = anc.parent_tax_id
        WHERE p.tax_id != anc.tax_id AND anc.depth < 64
      )
      SELECT 1 FROM anc
      WHERE depth > 0 AND LOWER(rank) = 'species'
      LIMIT 1;
      ''',
      [taxId],
    );
    return rows.isNotEmpty;
  }

  List<TaxonNode> getChildren(
    int parentTaxId, {
    bool hideNonSpecific = false,
    bool hideSubspecies = false,
    int? limit,
    int offset = 0,
  }) {
    if (hideSubspecies) {
      final parent = getNode(parentTaxId);
      if (parent != null) {
        final parentRank = parent.rank.trim().toLowerCase();
        if (parentRank == 'species' ||
            isInfraspecificRank(parentRank) ||
            hasSpeciesAncestor(parentTaxId)) {
          return const [];
        }
      }
    }

    final nonSpecificClause =
        hideNonSpecific ? nonSpecificSqlExclusionClause('scientific_name') : '';
    final subspeciesClause =
        hideSubspecies ? infraspecificRankSqlExclusionClause('rank') : '';
    final limitClause = limit != null ? 'LIMIT ? OFFSET ?' : '';
    final params = <Object?>[
      parentTaxId,
      if (limit != null) ...[limit, offset],
    ];
    final rows = db.select(
      '''
      SELECT tax_id, parent_tax_id, rank, scientific_name, child_count
      FROM nodes
      WHERE parent_tax_id = ? AND tax_id != parent_tax_id
        $nonSpecificClause
        $subspeciesClause
      ORDER BY scientific_name COLLATE NOCASE ASC
      $limitClause;
      ''',
      params,
    );
    return rows.map(_rowToNode).toList();
  }

  TaxonNode? getNode(int taxId) {
    final rows = db.select(
      '''
      SELECT tax_id, parent_tax_id, rank, scientific_name, child_count
      FROM nodes
      WHERE tax_id = ?;
      ''',
      [taxId],
    );
    if (rows.isEmpty) return null;
    return _rowToNode(rows.first);
  }

  List<TaxonNode> getLineage(int taxId) {
    final rows = db.select(
      '''
      WITH RECURSIVE anc(tax_id, parent_tax_id, rank, scientific_name, child_count, depth) AS (
        SELECT tax_id, parent_tax_id, rank, scientific_name, child_count, 0
        FROM nodes
        WHERE tax_id = ?
        UNION ALL
        SELECT p.tax_id, p.parent_tax_id, p.rank, p.scientific_name, p.child_count, anc.depth + 1
        FROM nodes p
        JOIN anc ON p.tax_id = anc.parent_tax_id
        WHERE p.tax_id != anc.tax_id AND anc.depth < 64
      )
      SELECT tax_id, parent_tax_id, rank, scientific_name, child_count
      FROM anc
      ORDER BY depth DESC;
      ''',
      [taxId],
    );
    return rows.map(_rowToNode).toList();
  }

  TaxonDetails? getTaxonDetails(
    int taxId, {
    bool hideNonSpecific = false,
    bool hideSubspecies = false,
  }) {
    final node = getNode(taxId);
    if (node == null) return null;

    final nameRows = db.select(
      '''
      SELECT name_txt, name_class
      FROM names
      WHERE tax_id = ?
      ORDER BY
        CASE name_class
          WHEN 'scientific name' THEN 0
          WHEN 'genbank common name' THEN 1
          WHEN 'common name' THEN 2
          ELSE 3
        END,
        name_txt COLLATE NOCASE ASC;
      ''',
      [taxId],
    );

    final names = nameRows
        .map(
          (r) => TaxonName(
            nameTxt: r['name_txt'] as String,
            nameClass: r['name_class'] as String,
          ),
        )
        .toList();

    return TaxonDetails(
      node: node,
      names: names,
      lineage: getLineage(taxId),
      children: getChildren(
        taxId,
        hideNonSpecific: hideNonSpecific,
        hideSubspecies: hideSubspecies,
      ),
    );
  }

  List<SearchResult> fuzzySearch(
    String query, {
    NameFilter filter = NameFilter.all,
    bool hideNonSpecific = false,
    bool hideSubspecies = false,
    int limit = 40,
  }) {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final classClause = _filterClause(filter);
    final nonSpecificClause = hideNonSpecific
        ? nonSpecificSqlExclusionClause('nd.scientific_name')
        : '';
    final subspeciesClause = hideSubspecies
        ? '''
          ${infraspecificRankSqlExclusionClause('nd.rank')}
          AND NOT EXISTS (
            SELECT 1 FROM nodes p
            WHERE p.tax_id = nd.parent_tax_id
              AND p.tax_id != nd.tax_id
              AND LOWER(p.rank) = 'species'
          )
        '''
        : '';
    final candidates = <int, _CandidateRow>{};

    // Stage 1A: Fast B-tree index range prefix match on idx_names_txt_nocase.
    // Using >= / < COLLATE NOCASE (instead of LIKE ... ESCAPE) guarantees
    // O(log N) index lookup instead of a 4M-row full table scan.
    final bounds = _prefixRangeBounds(q);
    if (bounds != null) {
      final prefixRows = db.select(
        '''
        SELECT n.id, n.tax_id, n.name_txt, n.name_class, nd.scientific_name, nd.rank
        FROM names n
        JOIN nodes nd ON nd.tax_id = n.tax_id
        WHERE n.name_txt >= ? COLLATE NOCASE
          AND n.name_txt < ? COLLATE NOCASE
          $classClause
          $nonSpecificClause
          $subspeciesClause
        LIMIT 120;
        ''',
        [bounds.lower, bounds.upper],
      );
      for (final r in prefixRows) {
        final id = r['id'] as int;
        candidates[id] = _CandidateRow.fromSql(r);
      }
    }

    // Stage 1B: Fast FTS5 trigram exact-substring phrase match (intersects
    // trigram posting lists; no ORDER BY bm25 full-corpus sort).
    if (q.length >= 3 && candidates.length < limit) {
      final phraseExpr = '"${q.replaceAll('"', '""')}"';
      final phraseRows = db.select(
        '''
        SELECT n.id, n.tax_id, n.name_txt, n.name_class, nd.scientific_name, nd.rank
        FROM names_fts f
        JOIN names n ON n.id = f.rowid
        JOIN nodes nd ON nd.tax_id = n.tax_id
        WHERE names_fts MATCH ?
          $classClause
          $nonSpecificClause
          $subspeciesClause
        LIMIT 200;
        ''',
        [phraseExpr],
      );
      for (final r in phraseRows) {
        final id = r['id'] as int;
        candidates.putIfAbsent(id, () => _CandidateRow.fromSql(r));
      }
    }

    // Stage 1C: Selective typo-tolerant fallback ONLY when prefix + phrase
    // matches found very few candidates. Uses 2-4 selective chunks (words or
    // prefix/suffix halves) without full-corpus bm25 sorting.
    if (q.length >= 4 && candidates.length < 15) {
      final typoExpr = _buildSelectiveTypoQuery(q);
      if (typoExpr.isNotEmpty) {
        final typoRows = db.select(
          '''
          SELECT n.id, n.tax_id, n.name_txt, n.name_class, nd.scientific_name, nd.rank
          FROM names_fts f
          JOIN names n ON n.id = f.rowid
          JOIN nodes nd ON nd.tax_id = n.tax_id
          WHERE names_fts MATCH ?
            $classClause
            $nonSpecificClause
            $subspeciesClause
          LIMIT 300;
          ''',
          [typoExpr],
        );
        for (final r in typoRows) {
          final id = r['id'] as int;
          candidates.putIfAbsent(id, () => _CandidateRow.fromSql(r));
        }
      }
    }

    // Stage 2: Fuzzy re-rank & deduplicate by tax_id.
    final belowSpeciesCache = <int, bool>{};
    final bestByTaxId = <int, SearchResult>{};
    for (final c in candidates.values) {
      if (hideSubspecies) {
        final below = belowSpeciesCache.putIfAbsent(
          c.taxId,
          () => isInfraspecificRank(c.rank) || hasSpeciesAncestor(c.taxId),
        );
        if (below) continue;
      }
      final score = scoreFuzzyMatch(
        query: q,
        candidateName: c.nameTxt,
        nameClass: c.nameClass,
      );
      final existing = bestByTaxId[c.taxId];
      if (existing == null || score > existing.score) {
        bestByTaxId[c.taxId] = SearchResult(
          taxId: c.taxId,
          matchedName: c.nameTxt,
          nameClass: c.nameClass,
          scientificName: c.scientificName,
          rank: c.rank,
          score: score,
        );
      }
    }

    final sorted = bestByTaxId.values.toList()
      ..sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return a.scientificName.compareTo(b.scientificName);
      });

    if (sorted.length > limit) {
      return sorted.sublist(0, limit);
    }
    return sorted;
  }

  static String _filterClause(NameFilter filter) {
    return switch (filter) {
      NameFilter.all => '',
      NameFilter.scientific =>
        "AND n.name_class IN ('scientific name', 'synonym', 'equivalent name')",
      NameFilter.common =>
        "AND n.name_class IN ('common name', 'genbank common name', 'blast name')",
    };
  }

  static ({String lower, String upper})? _prefixRangeBounds(String query) {
    final lower = query.toLowerCase();
    if (lower.isEmpty) return null;
    final lastCode = lower.codeUnitAt(lower.length - 1);
    if (lastCode >= 0xFFFF) return null;
    final upper =
        lower.substring(0, lower.length - 1) + String.fromCharCode(lastCode + 1);
    return (lower: lower, upper: upper);
  }

  static String _buildSelectiveTypoQuery(String query) {
    final clean = query.trim();
    if (clean.length < 4) return '';

    final chunks = <String>{};
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toList();

    for (final w in words) {
      if (w.length >= 4) {
        chunks.add('"${w.replaceAll('"', '""')}"');
        if (chunks.length >= 2) break;
      }
    }

    // Add prefix and suffix halves of the longest word (or full query) so a
    // single typo inside a word still matches the uncorrupted half.
    final target = words.isNotEmpty
        ? (words..sort((a, b) => b.length.compareTo(a.length))).first
        : clean;
    if (target.length >= 5) {
      final halfLen = (target.length ~/ 2).clamp(3, 5);
      final left = target.substring(0, halfLen);
      final right = target.substring(target.length - halfLen);
      chunks.add('"${left.replaceAll('"', '""')}"');
      chunks.add('"${right.replaceAll('"', '""')}"');
    } else if (chunks.isEmpty) {
      chunks.add('"${clean.substring(0, 3).replaceAll('"', '""')}"');
      chunks.add(
        '"${clean.substring(clean.length - 3).replaceAll('"', '""')}"',
      );
    }

    return chunks.take(4).join(' OR ');
  }

  static TaxonNode _rowToNode(Row r) {
    return TaxonNode(
      taxId: r['tax_id'] as int,
      parentTaxId: r['parent_tax_id'] as int,
      rank: r['rank'] as String,
      scientificName: r['scientific_name'] as String,
      childCount: r['child_count'] as int,
    );
  }
}

class _CandidateRow {
  const _CandidateRow({
    required this.taxId,
    required this.nameTxt,
    required this.nameClass,
    required this.scientificName,
    required this.rank,
  });

  factory _CandidateRow.fromSql(Row r) {
    return _CandidateRow(
      taxId: r['tax_id'] as int,
      nameTxt: r['name_txt'] as String,
      nameClass: r['name_class'] as String,
      scientificName: r['scientific_name'] as String,
      rank: r['rank'] as String,
    );
  }

  final int taxId;
  final String nameTxt;
  final String nameClass;
  final String scientificName;
  final String rank;
}
