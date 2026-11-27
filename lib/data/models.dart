enum NameFilter { all, scientific, common }

class TaxonNode {
  const TaxonNode({
    required this.taxId,
    required this.parentTaxId,
    required this.rank,
    required this.scientificName,
    required this.childCount,
  });

  final int taxId;
  final int parentTaxId;
  final String rank;
  final String scientificName;
  final int childCount;
}

class TaxonName {
  const TaxonName({
    required this.nameTxt,
    required this.nameClass,
  });

  final String nameTxt;
  final String nameClass;
}

class TaxonDetails {
  const TaxonDetails({
    required this.node,
    required this.names,
    required this.lineage,
    required this.children,
  });

  final TaxonNode node;
  final List<TaxonName> names;
  final List<TaxonNode> lineage;
  final List<TaxonNode> children;
}

class SearchResult {
  const SearchResult({
    required this.taxId,
    required this.matchedName,
    required this.nameClass,
    required this.scientificName,
    required this.rank,
    required this.score,
  });

  final int taxId;
  final String matchedName;
  final String nameClass;
  final String scientificName;
  final String rank;
  final double score;
}

class DatabaseStatus {
  const DatabaseStatus({
    required this.exists,
    required this.dbPath,
    this.nodeCount = 0,
    this.nameCount = 0,
    this.etag,
    this.lastModified,
    this.updatedAt,
  });

  final bool exists;
  final String dbPath;
  final int nodeCount;
  final int nameCount;
  final String? etag;
  final String? lastModified;
  final DateTime? updatedAt;
}

enum IngestStage {
  checking,
  downloading,
  extracting,
  parsingNodes,
  parsingNames,
  indexing,
  finalizing,
  done,
}

class IngestProgress {
  const IngestProgress({
    required this.stage,
    required this.message,
    this.fraction,
  });

  final IngestStage stage;
  final String message;
  final double? fraction;
}
