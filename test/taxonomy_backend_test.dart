import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncbi_taxonomy_explorer/data/dmp_parser.dart';
import 'package:ncbi_taxonomy_explorer/data/fuzzy_scorer.dart';
import 'package:ncbi_taxonomy_explorer/data/models.dart';
import 'package:ncbi_taxonomy_explorer/data/ncbi_sync_service.dart';
import 'package:ncbi_taxonomy_explorer/data/taxon_filter.dart';
import 'package:ncbi_taxonomy_explorer/data/taxonomy_database.dart';
import 'package:ncbi_taxonomy_explorer/state/search_worker.dart';
import 'package:path/path.dart' as p;

const _sampleNodesDmp = [
  '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
  '131567\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
  '2759\t|\t131567\t|\tsuperkingdom\t|\t\t|\t0\t|',
  '33208\t|\t2759\t|\tkingdom\t|\t\t|\t0\t|',
  '40674\t|\t33208\t|\tclass\t|\t\t|\t0\t|',
  '9604\t|\t40674\t|\tfamily\t|\t\t|\t0\t|',
  '9606\t|\t9604\t|\tspecies\t|\t\t|\t0\t|',
  '9598\t|\t9604\t|\tspecies\t|\t\t|\t0\t|',
  '9685\t|\t40674\t|\tspecies\t|\t\t|\t0\t|',
];

const _sampleNamesDmp = [
  '1\t|\troot\t|\t\t|\tscientific name\t|',
  '131567\t|\tcellular organisms\t|\t\t|\tscientific name\t|',
  '2759\t|\tEukaryota\t|\t\t|\tscientific name\t|',
  '33208\t|\tMetazoa\t|\t\t|\tscientific name\t|',
  '33208\t|\tanimals\t|\t\t|\tcommon name\t|',
  '40674\t|\tMammalia\t|\t\t|\tscientific name\t|',
  '40674\t|\tmammals\t|\t\t|\tgenbank common name\t|',
  '9604\t|\tHominidae\t|\t\t|\tscientific name\t|',
  '9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|',
  '9606\t|\thuman\t|\t\t|\tgenbank common name\t|',
  '9598\t|\tPan troglodytes\t|\t\t|\tscientific name\t|',
  '9598\t|\tchimpanzee\t|\t\t|\tgenbank common name\t|',
  '9685\t|\tFelis catus\t|\t\t|\tscientific name\t|',
  '9685\t|\tdomestic cat\t|\t\t|\tgenbank common name\t|',
  '9685\t|\tFelis silvestris catus\t|\t\t|\tsynonym\t|',
];

void main() {
  group('dmp_parser', () {
    test('parses nodes.dmp and names.dmp lines', () {
      final node = parseNodesLine('9606\t|\t9605\t|\tspecies\t|\t\t|\t0\t|');
      expect(node, isNotNull);
      expect(node!.taxId, 9606);
      expect(node.parentTaxId, 9605);
      expect(node.rank, 'species');

      final name = parseNamesLine(
        '9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|',
      );
      expect(name, isNotNull);
      expect(name!.taxId, 9606);
      expect(name.nameTxt, 'Homo sapiens');
      expect(name.nameClass, 'scientific name');

      expect(parseNodesLine(''), isNull);
      expect(parseNamesLine('bad line'), isNull);
    });
  });

  group('fuzzy_scorer', () {
    test('computes Damerau-Levenshtein and ranks exact > typo', () {
      expect(damerauLevenshtein('sapiens', 'sapens'), 1);
      expect(damerauLevenshtein('catus', 'ctaus'), 1);

      final exact = scoreFuzzyMatch(
        query: 'Homo sapiens',
        candidateName: 'Homo sapiens',
        nameClass: 'scientific name',
      );
      final typo = scoreFuzzyMatch(
        query: 'Homo sapens',
        candidateName: 'Homo sapiens',
        nameClass: 'scientific name',
      );
      expect(exact, greaterThan(typo));
      expect(typo, greaterThan(0.8));
    });
  });

  group('TaxonomyRepository (SQLite + FTS5)', () {
    late TaxonomyRepository repo;

    setUp(() {
      repo = TaxonomyRepository.openInMemory();
      final counts = TaxonomyRepository.populateFromLines(
        db: repo.db,
        nodesLines: _sampleNodesDmp,
        namesLines: _sampleNamesDmp,
        metadata: const {'etag': '"abc123"'},
      );
      expect(counts.nodeCount, _sampleNodesDmp.length);
      expect(counts.nameCount, _sampleNamesDmp.length);
    });

    tearDown(() => repo.close());

    test('browses children without root self-loop', () {
      final rootChildren = repo.getChildren(1);
      expect(rootChildren.map((n) => n.taxId), [131567]);

      final hominidaeChildren = repo.getChildren(9604);
      expect(
        hominidaeChildren.map((n) => n.scientificName),
        ['Homo sapiens', 'Pan troglodytes'],
      );
    });

    test('computes lineage via recursive CTE', () {
      final lineage = repo.getLineage(9606);
      expect(
        lineage.map((n) => n.taxId),
        [1, 131567, 2759, 33208, 40674, 9604, 9606],
      );
    });

    test('loads taxon details and status', () {
      final details = repo.getTaxonDetails(9685);
      expect(details, isNotNull);
      expect(details!.node.scientificName, 'Felis catus');
      expect(details.names.length, 3);

      final status = repo.getStatus();
      expect(status.nodeCount, _sampleNodesDmp.length);
      expect(status.etag, '"abc123"');
    });

    test('fuzzy searches scientific names, typos, and common names', () {
      final exact = repo.fuzzySearch('Homo sapiens');
      expect(exact.first.taxId, 9606);

      final typo = repo.fuzzySearch('Homo sapens');
      expect(typo, isNotEmpty);
      expect(typo.first.taxId, 9606);

      final common = repo.fuzzySearch('domestic cat', filter: NameFilter.common);
      expect(common.first.taxId, 9685);

      final sciOnly = repo.fuzzySearch('human', filter: NameFilter.scientific);
      expect(sciOnly.where((r) => r.taxId == 9606), isEmpty);
    });

    test('filters out non-specific taxa in tree and search', () {
      expect(isNonSpecificTaxonName('Candidatus Pelagibacter'), isTrue);
      expect(isNonSpecificTaxonName('Bacillus sp. 123'), isTrue);
      expect(isNonSpecificTaxonName('Fungi incertae sedis'), isTrue);
      expect(isNonSpecificTaxonName('unclassified Bacteria'), isTrue);
      expect(isNonSpecificTaxonName('Homo sapiens'), isFalse);

      final extraRepo = TaxonomyRepository.openInMemory();
      addTearDown(extraRepo.close);
      TaxonomyRepository.populateFromLines(
        db: extraRepo.db,
        nodesLines: const [
          '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
          '10\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
          '11\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
          '12\t|\t1\t|\tno rank\t|\t\t|\t0\t|',
          '13\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
        ],
        namesLines: const [
          '1\t|\troot\t|\t\t|\tscientific name\t|',
          '10\t|\tCandidatus Pelagibacter\t|\t\t|\tscientific name\t|',
          '11\t|\tBacillus sp. 123\t|\t\t|\tscientific name\t|',
          '12\t|\tFungi incertae sedis\t|\t\t|\tscientific name\t|',
          '13\t|\tBacillus subtilis\t|\t\t|\tscientific name\t|',
        ],
      );

      expect(extraRepo.getChildren(1, hideNonSpecific: false).length, 4);
      final filteredChildren = extraRepo.getChildren(1, hideNonSpecific: true);
      expect(filteredChildren.map((n) => n.scientificName), ['Bacillus subtilis']);

      final unfilteredSearch =
          extraRepo.fuzzySearch('Bacillus', hideNonSpecific: false);
      expect(
        unfilteredSearch.map((r) => r.scientificName),
        containsAll(['Bacillus sp. 123', 'Bacillus subtilis']),
      );

      final filteredSearch =
          extraRepo.fuzzySearch('Bacillus', hideNonSpecific: true);
      expect(filteredSearch.map((r) => r.scientificName), ['Bacillus subtilis']);
    });

    test('compactImport prunes non-specific leaves without orphaning children',
        () {
      final compactRepo = TaxonomyRepository.openInMemory();
      addTearDown(compactRepo.close);
      final counts = TaxonomyRepository.populateFromLines(
        db: compactRepo.db,
        compactImport: true,
        nodesLines: const [
          '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
          '10\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
          '20\t|\t1\t|\tno rank\t|\t\t|\t0\t|',
          '21\t|\t20\t|\tspecies\t|\t\t|\t0\t|',
        ],
        namesLines: const [
          '1\t|\troot\t|\t\t|\tscientific name\t|',
          '10\t|\tBacillus sp. 123\t|\t\t|\tscientific name\t|',
          '20\t|\tunclassified Bacteria\t|\t\t|\tscientific name\t|',
          '21\t|\tEscherichia coli\t|\t\t|\tscientific name\t|',
        ],
      );

      expect(counts.nodeCount, 3);
      expect(compactRepo.getNode(10), isNull);
      expect(compactRepo.getNode(20), isNotNull);
      expect(compactRepo.getLineage(21).map((n) => n.taxId), [1, 20, 21]);
    });

    test('hideSubspecies excludes everything below species in tree and search',
        () {
      final subRepo = TaxonomyRepository.openInMemory();
      addTearDown(subRepo.close);
      TaxonomyRepository.populateFromLines(
        db: subRepo.db,
        nodesLines: const [
          '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
          '561\t|\t1\t|\tgenus\t|\t\t|\t0\t|',
          '562\t|\t561\t|\tspecies\t|\t\t|\t0\t|',
          '83333\t|\t562\t|\tno rank\t|\t\t|\t0\t|',
          '511145\t|\t83333\t|\tno rank\t|\t\t|\t0\t|',
          '83334\t|\t562\t|\tstrain\t|\t\t|\t0\t|',
        ],
        namesLines: const [
          '1\t|\troot\t|\t\t|\tscientific name\t|',
          '561\t|\tEscherichia\t|\t\t|\tscientific name\t|',
          '562\t|\tEscherichia coli\t|\t\t|\tscientific name\t|',
          '83333\t|\tEscherichia coli K-12\t|\t\t|\tscientific name\t|',
          '511145\t|\tEscherichia coli str. K-12 substr. MG1655\t|\t\t|\tscientific name\t|',
          '83334\t|\tEscherichia coli O157:H7\t|\t\t|\tscientific name\t|',
        ],
      );

      expect(subRepo.getChildren(562, hideSubspecies: false).length, 2);
      expect(subRepo.getChildren(562, hideSubspecies: true), isEmpty);
      expect(
        subRepo.getTaxonDetails(562, hideSubspecies: true)!.children,
        isEmpty,
      );

      final allResults =
          subRepo.fuzzySearch('Escherichia coli', hideSubspecies: false);
      expect(allResults.map((r) => r.taxId), containsAll([562, 83333, 511145, 83334]));

      final filteredResults =
          subRepo.fuzzySearch('Escherichia coli', hideSubspecies: true);
      expect(filteredResults.map((r) => r.taxId), [562, 561]);
    });
  });

  group('NcbiSyncService tar.gz extraction', () {
    test('streams only nodes.dmp and names.dmp from tar.gz', () async {
      final tempDir = await Directory.systemTemp.createTemp('tar_test_');
      try {
        final archive = Archive()
          ..addFile(
            ArchiveFile.bytes(
              'readme.txt',
              utf8.encode('ignored file'),
            ),
          )
          ..addFile(
            ArchiveFile.bytes(
              'nodes.dmp',
              utf8.encode('${_sampleNodesDmp.join('\n')}\n'),
            ),
          )
          ..addFile(
            ArchiveFile.bytes(
              'names.dmp',
              utf8.encode('${_sampleNamesDmp.join('\n')}\n'),
            ),
          );

        final tarBytes = TarEncoder().encode(archive);
        final gzBytes = GZipEncoder().encode(tarBytes);
        final tarGzFile = File(p.join(tempDir.path, 'test_taxdump.tar.gz'));
        await tarGzFile.writeAsBytes(gzBytes);

        final outDir = Directory(p.join(tempDir.path, 'out'))..createSync();
        final extracted = await extractDmpFilesFromTarGz(
          tarGzFile: tarGzFile,
          outputDir: outDir,
          targetNames: const {'nodes.dmp', 'names.dmp'},
        );

        expect(extracted.keys.toSet(), {'nodes.dmp', 'names.dmp'});
        expect(File(p.join(outDir.path, 'readme.txt')).existsSync(), isFalse);
        expect(
          await extracted['nodes.dmp']!.readAsString(),
          contains('9606'),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('SearchWorker background isolate', () {
    test('runs fuzzy search off the main isolate and closes cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('search_worker_');
      final dbPath = p.join(tempDir.path, 'taxonomy.db');
      final worker = SearchWorker();
      try {
        final repo = TaxonomyRepository.openFile(dbPath);
        TaxonomyRepository.populateFromLines(
          db: repo.db,
          nodesLines: _sampleNodesDmp,
          namesLines: _sampleNamesDmp,
        );
        repo.close();

        await worker.start(dbPath);
        final results = await worker.search(
          query: 'Homo sapens',
          filter: NameFilter.all,
          hideNonSpecific: true,
          hideSubspecies: true,
        );
        expect(results, isNotEmpty);
        expect(results.first.taxId, 9606);

        await worker.close();
        // Verify SQLite file handle was released on Windows.
        File(dbPath).deleteSync();
      } finally {
        await worker.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
