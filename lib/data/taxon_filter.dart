/// Returns `true` if [scientificName] represents a non-specific, provisional,
/// or unplaced taxon (e.g. `Candidatus`, `sp.`, `incertae sedis`,
/// `unclassified`, `uncultured`, `environmental samples`, `metagenome`).
bool isNonSpecificTaxonName(String scientificName) {
  final s = scientificName.trim().toLowerCase();
  if (s.isEmpty) return false;
  if (s.startsWith('candidatus ')) return true;
  if (s.contains(' sp.') || s.endsWith(' sp')) return true;
  if (s.contains('incertae sedis')) return true;
  if (s.startsWith('unclassified ')) return true;
  if (s.startsWith('uncultured ')) return true;
  if (s.contains('environmental samples')) return true;
  if (s == 'metagenome' || s.endsWith(' metagenome') || s == 'metagenomes') {
    return true;
  }
  if (s == 'other sequences') return true;
  return false;
}

/// Returns a SQL boolean expression matching non-specific taxa based on
/// [columnExpr] (e.g. `scientific_name` or `nd.scientific_name`).
String nonSpecificSqlMatchExpr(String columnExpr) {
  final col = 'LOWER($columnExpr)';
  return '''(
    $col LIKE 'candidatus %'
    OR $col LIKE '% sp.%'
    OR $col LIKE '% sp'
    OR $col LIKE '%incertae sedis%'
    OR $col LIKE 'unclassified %'
    OR $col LIKE 'uncultured %'
    OR $col LIKE '%environmental samples%'
    OR $col = 'metagenome'
    OR $col LIKE '% metagenome'
    OR $col = 'metagenomes'
    OR $col = 'other sequences'
  )''';
}

/// Returns a SQL `AND NOT (...)` clause excluding non-specific taxa based on
/// [columnExpr].
String nonSpecificSqlExclusionClause(String columnExpr) {
  return 'AND NOT ${nonSpecificSqlMatchExpr(columnExpr)}';
}

/// NCBI Taxonomy ranks strictly below `species`.
const Set<String> infraspecificRanks = {
  'subspecies',
  'strain',
  'serotype',
  'serogroup',
  'biotype',
  'forma',
  'forma specialis',
  'varietas',
  'subvariety',
  'isolate',
  'morph',
  'pathogroup',
  'genotype',
  'ecotype',
  'breed',
  'cultivar',
  'chemovar',
  'biovar',
  'serovar',
  'pathovar',
  'subform',
};

/// Returns `true` if [rank] is an explicit rank below `species`.
bool isInfraspecificRank(String rank) {
  return infraspecificRanks.contains(rank.trim().toLowerCase());
}

/// Returns a SQL `AND (...)` clause excluding explicit infraspecific ranks
/// based on [rankColExpr] (e.g. `rank` or `nd.rank`).
String infraspecificRankSqlExclusionClause(String rankColExpr) {
  final quoted = infraspecificRanks.map((r) => "'$r'").join(', ');
  return 'AND LOWER($rankColExpr) NOT IN ($quoted)';
}

