/// Preprocesses NCBI taxonomy scientific names for clearer Anglicized English
/// text-to-speech pronunciation.
String formatScientificNameForAnglicizedTts(String scientificName) {
  var cleaned = scientificName
      .replaceAll(_nonSpokenPunctuationPattern, '')
      .replaceAll(_whitespacePattern, ' ')
      .trim();

  if (cleaned.isEmpty) {
    return '';
  }

  for (final rule in _abbreviationRules) {
    cleaned = cleaned.replaceAll(rule.pattern, rule.replacement);
  }

  cleaned = cleaned.replaceAll(_whitespacePattern, ' ').trim();
  if (cleaned.isEmpty) {
    return '';
  }

  return cleaned.split(' ').map(_transformToken).join(' ');
}

String _transformToken(String token) {
  final match = _wrappedAlphabeticTokenPattern.firstMatch(token);
  if (match == null) {
    return token;
  }

  final leadingPunct = match.group(1)!;
  final core = match.group(2)!;
  final trailingPunct = match.group(3)!;

  final transformed = _transformLatinateWord(core);
  return '$leadingPunct$transformed$trailingPunct';
}

String _transformLatinateWord(String word) {
  final lower = word.toLowerCase();
  if (_skipWords.contains(lower)) {
    return word;
  }

  final firstCodeUnit = word.codeUnitAt(0);
  final startsWithUppercase = firstCodeUnit >= 65 && firstCodeUnit <= 90;

  var normalized = lower;
  for (final rule in _leadingSilentClusterRules) {
    if (rule.pattern.hasMatch(normalized)) {
      normalized = normalized.replaceFirst(rule.pattern, rule.replacement);
      break;
    }
  }

  var stem = normalized;
  var suffixHint = '';
  for (final rule in _suffixRules) {
    if (normalized.length >= rule.minWordLength &&
        normalized.endsWith(rule.suffix)) {
      stem = normalized.substring(0, normalized.length - rule.suffix.length);
      suffixHint = rule.replacement;
      break;
    }
  }

  stem = stem.replaceAll(_chDigraphPattern, 'k');
  stem = stem.replaceAll(_aeDigraphPattern, 'ee');
  stem = stem.replaceAll(_oeDigraphPattern, 'ee');

  final result = '$stem$suffixHint';
  if (result.isEmpty) {
    return word;
  }

  if (startsWithUppercase) {
    return '${result[0].toUpperCase()}${result.substring(1)}';
  }
  return result;
}

class _RegexRule {
  const _RegexRule(this.pattern, this.replacement);

  final RegExp pattern;
  final String replacement;
}

class _SuffixRule {
  const _SuffixRule({
    required this.suffix,
    required this.minWordLength,
    required this.replacement,
  });

  final String suffix;
  final int minWordLength;
  final String replacement;
}

final RegExp _nonSpokenPunctuationPattern = RegExp(r'''[\[\]'"‘’“”]''');
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _wrappedAlphabeticTokenPattern =
    RegExp(r'^([({]*)([A-Za-z]+)([),;:}]*)$');

final RegExp _chDigraphPattern = RegExp(r'(?<!s)ch');
final RegExp _aeDigraphPattern = RegExp(r'ae(?!r)');
final RegExp _oeDigraphPattern = RegExp(r'oe(?=[bcdfghjklmnpqrstvwxz])');

final List<_RegexRule> _abbreviationRules = [
  _RegexRule(
    RegExp(r'(?<![\w.])f\.\s*sp\.(?!\w)', caseSensitive: false),
    'forma specialis',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])(?:subsp|ssp)\.(?!\w)', caseSensitive: false),
    'subspecies',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])var\.(?!\w)', caseSensitive: false),
    'variety',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])f\.(?!\w)', caseSensitive: false),
    'forma',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])spp?\.(?!\w)', caseSensitive: false),
    'species',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])aff\.(?!\w)', caseSensitive: false),
    'affinis',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])cf\.(?!\w)', caseSensitive: false),
    'confer',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])ser\.(?!\w)', caseSensitive: false),
    'series',
  ),
  _RegexRule(
    RegExp(r'(?<![\w.])str\.(?!\w)', caseSensitive: false),
    'strain',
  ),
];

final List<_RegexRule> _leadingSilentClusterRules = [
  _RegexRule(RegExp(r'^pt(?=[aeiouy])'), 't'),
  _RegexRule(RegExp(r'^ps(?=[aeiouy])'), 's'),
  _RegexRule(RegExp(r'^cn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^ct(?=[aeiouy])'), 't'),
  _RegexRule(RegExp(r'^mn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^pn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^gn(?=[aeiouy])'), 'n'),
];

/// Ordered longest suffix first so at most one suffix rule applies per word.
const List<_SuffixRule> _suffixRules = [
  _SuffixRule(suffix: 'oideae', minWordLength: 7, replacement: 'oy-dee-ee'),
  _SuffixRule(suffix: 'aceae', minWordLength: 6, replacement: 'ay-see-ee'),
  _SuffixRule(suffix: 'cetes', minWordLength: 7, replacement: 'see-teez'),
  _SuffixRule(suffix: 'idae', minWordLength: 6, replacement: 'ih-dee'),
  _SuffixRule(suffix: 'inae', minWordLength: 6, replacement: 'eye-nee'),
  _SuffixRule(suffix: 'ales', minWordLength: 6, replacement: 'ay-leez'),
  _SuffixRule(suffix: 'ii', minWordLength: 4, replacement: 'ee-eye'),
];

const Set<String> _skipWords = {
  'root',
  'cellular',
  'organism',
  'organisms',
  'species',
  'subspecies',
  'variety',
  'forma',
  'specialis',
  'strain',
  'series',
  'affinis',
  'confer',
  'virus',
  'viruses',
  'unclassified',
  'uncultured',
  'environmental',
  'sample',
  'samples',
  'other',
  'sequence',
  'sequences',
  'metagenome',
  'group',
  'complex',
  'clade',
  'hybrid',
  'candidatus',
  'incertae',
  'sedis',
  'synthetic',
  'construct',
  'vector',
  'eukaryotes',
  'bacteria',
  'bacterium',
};
