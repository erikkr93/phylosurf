class ParsedNode {
  const ParsedNode({
    required this.taxId,
    required this.parentTaxId,
    required this.rank,
  });

  final int taxId;
  final int parentTaxId;
  final String rank;
}

class ParsedName {
  const ParsedName({
    required this.taxId,
    required this.nameTxt,
    required this.nameClass,
  });

  final int taxId;
  final String nameTxt;
  final String nameClass;
}

const _sep = '\t|\t';

/// Parses a single line from NCBI `nodes.dmp`.
/// Returns `null` for blank or malformed lines.
ParsedNode? parseNodesLine(String line) {
  if (line.isEmpty) return null;

  final s1 = line.indexOf(_sep);
  if (s1 <= 0) return null;

  final s2 = line.indexOf(_sep, s1 + _sep.length);
  if (s2 <= s1 + _sep.length) return null;

  var s3 = line.indexOf(_sep, s2 + _sep.length);
  if (s3 < 0) {
    final end = line.endsWith('\t|') ? line.length - 2 : line.length;
    s3 = end;
  }
  if (s3 < s2 + _sep.length) return null;

  final taxId = int.tryParse(line.substring(0, s1).trim());
  final parentTaxId =
      int.tryParse(line.substring(s1 + _sep.length, s2).trim());
  if (taxId == null || parentTaxId == null) return null;

  final rank = line.substring(s2 + _sep.length, s3).trim();
  return ParsedNode(taxId: taxId, parentTaxId: parentTaxId, rank: rank);
}

/// Parses a single line from NCBI `names.dmp`.
/// Format: `tax_id \t|\t name_txt \t|\t unique_name \t|\t name_class \t|`
/// Returns `null` for blank or malformed lines.
ParsedName? parseNamesLine(String line) {
  if (line.isEmpty) return null;

  final s1 = line.indexOf(_sep);
  if (s1 <= 0) return null;

  final s2 = line.indexOf(_sep, s1 + _sep.length);
  if (s2 < 0) return null;

  final s3 = line.indexOf(_sep, s2 + _sep.length);
  if (s3 < 0) return null;

  final taxId = int.tryParse(line.substring(0, s1).trim());
  if (taxId == null) return null;

  final nameTxt = line.substring(s1 + _sep.length, s2).trim();
  if (nameTxt.isEmpty) return null;

  var end = line.indexOf('\t|', s3 + _sep.length);
  if (end < 0) end = line.length;
  final nameClass = line.substring(s3 + _sep.length, end).trim();
  if (nameClass.isEmpty) return null;

  return ParsedName(taxId: taxId, nameTxt: nameTxt, nameClass: nameClass);
}
