// Pure-Dart Anglicized scientific name to KittenTTS IPA phonemizer.
//
// Converts NCBI taxonomy scientific names into IPA phoneme strings restricted
// to KittenTTS Nano's valid token vocabulary (`tokens.txt`).

/// Maximum rune length emitted for KittenTTS inference input.
const int _kMaxKittenIpaRunes = 380;

/// Exact valid Unicode codepoints accepted by KittenTTS Nano (`tokens.txt`).
const Set<int> kKittenValidTokenCodepoints = {
  // ASCII punctuation and space: space ! " $ ' , . : ; ?
  0x0020, // ' '
  0x0021, // '!'
  0x0022, // '"'
  0x0024, // '$'
  0x0027, // "'"
  0x002C, // ','
  0x002E, // '.'
  0x003A, // ':'
  0x003B, // ';'
  0x003F, // '?'

  // ASCII uppercase A-Z
  0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, 0x0048, 0x0049,
  0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, 0x0050, 0x0051, 0x0052,
  0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0059, 0x005A,

  // ASCII lowercase a-z
  0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067, 0x0068, 0x0069,
  0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F, 0x0070, 0x0071, 0x0072,
  0x0073, 0x0074, 0x0075, 0x0076, 0x0077, 0x0078, 0x0079, 0x007A,

  // IPA symbols
  0x0251, // ɑ
  0x0250, // ɐ
  0x0252, // ɒ
  0x00E6, // æ
  0x0253, // ɓ
  0x0299, // ʙ
  0x03B2, // β
  0x0254, // ɔ
  0x0255, // ɕ
  0x00E7, // ç
  0x0257, // ɗ
  0x0256, // ɖ
  0x00F0, // ð
  0x02A4, // ʤ
  0x0259, // ə
  0x0258, // ɘ
  0x025A, // ɚ
  0x025B, // ɛ
  0x025C, // ɜ
  0x025D, // ɝ
  0x025E, // ɞ
  0x025F, // ɟ
  0x0284, // ʄ
  0x0261, // ɡ
  0x0260, // ɠ
  0x0262, // ɢ
  0x029B, // ʛ
  0x0266, // ɦ
  0x0267, // ɧ
  0x0127, // ħ
  0x0265, // ɥ
  0x029C, // ʜ
  0x0268, // ɨ
  0x026A, // ɪ
  0x029D, // ʝ
  0x026D, // ɭ
  0x026C, // ɬ
  0x026B, // ɫ
  0x026E, // ɮ
  0x029F, // ʟ
  0x0271, // ɱ
  0x026F, // ɯ
  0x0270, // ɰ
  0x014B, // ŋ
  0x0273, // ɳ
  0x0272, // ɲ
  0x0274, // ɴ
  0x00F8, // ø
  0x0275, // ɵ
  0x0278, // ɸ
  0x03B8, // θ
  0x0153, // œ
  0x0276, // ɶ
  0x0298, // ʘ
  0x0279, // ɹ
  0x027A, // ɺ
  0x027E, // ɾ
  0x027B, // ɻ
  0x0280, // ʀ
  0x0281, // ʁ
  0x027D, // ɽ
  0x0282, // ʂ
  0x0283, // ʃ
  0x0288, // ʈ
  0x02A7, // ʧ
  0x0289, // ʉ
  0x028A, // ʊ
  0x028B, // ʋ
  0x2C71, // ⱱ
  0x028C, // ʌ
  0x0263, // ɣ
  0x0264, // ɤ
  0x028D, // ʍ
  0x03C7, // χ
  0x028E, // ʎ
  0x028F, // ʏ
  0x0291, // ʑ
  0x0290, // ʐ
  0x0292, // ʒ
  0x0294, // ʔ
  0x02A1, // ʡ
  0x0295, // ʕ
  0x02A2, // ʢ
  0x01C0, // ǀ
  0x01C1, // ǁ
  0x01C2, // ǂ
  0x01C3, // ǃ
  0x02C8, // ˈ
  0x02CC, // ˌ
  0x02D0, // ː
  0x02D1, // ˑ
  0x02BC, // ʼ
  0x02B4, // ʴ
  0x02B0, // ʰ
  0x02B1, // ʱ
  0x02B2, // ʲ
  0x02B7, // ʷ
  0x02E0, // ˠ
  0x02E4, // ˤ
  0x02DE, // ˞
  0x2193, // ↓
  0x2191, // ↑
  0x2192, // →
  0x2197, // ↗
  0x2198, // ↘
  0x0329, // ̩
  0x1D7B, // ᵻ
};

/// Converts an NCBI scientific name into a KittenTTS-compatible Anglicized IPA
/// string.
///
/// The returned string is trimmed, contains strictly codepoints in
/// [kKittenValidTokenCodepoints], is at most 380 runes long (truncated cleanly
/// at a word boundary when possible), and returns `''` for blank or
/// unpronounceable input.
String phonemizeScientificNameToKittenIpa(String scientificName) {
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

  cleaned = _foldLatinDiacritics(cleaned)
      .replaceAll(_whitespacePattern, ' ')
      .trim();

  if (cleaned.isEmpty) {
    return '';
  }

  final ipaWords = <String>[];
  for (final rawToken in cleaned.split(' ')) {
    final subTokens = rawToken
        .split(_nonAlphanumericPattern)
        .where((segment) => segment.isNotEmpty);
    for (final segment in subTokens) {
      final phonemized = _phonemizeSegment(segment);
      if (phonemized.isNotEmpty) {
        ipaWords.addAll(phonemized);
      }
    }
  }

  if (ipaWords.isEmpty) {
    return '';
  }

  return _assembleAndFilter(ipaWords);
}

/// Converts an NCBI scientific name into KittenTTS IPA Unicode codepoints.
List<int> phonemizeScientificNameToKittenCodepoints(String scientificName) {
  return phonemizeScientificNameToKittenIpa(scientificName).runes.toList();
}

List<String> _phonemizeSegment(String segment) {
  final hasDigit = _digitPattern.hasMatch(segment);
  if (hasDigit) {
    return _spellAlphanumericCode(segment);
  }

  final lower = segment.toLowerCase();
  if (lower.length == 1) {
    final letterIpa = _letterNameIpa[lower];
    return letterIpa == null ? const [] : [letterIpa];
  }

  final known = _knownWordIpa[lower];
  if (known != null) {
    return [known];
  }

  final generated = _phonemizeLatinateWord(lower);
  return generated.isEmpty ? const [] : [generated];
}

List<String> _spellAlphanumericCode(String code) {
  final result = <String>[];
  final lower = code.toLowerCase();
  for (var i = 0; i < lower.length; i++) {
    final ch = lower[i];
    final digitIpa = _digitIpa[ch];
    if (digitIpa != null) {
      result.add(digitIpa);
      continue;
    }
    final letterIpa = _letterNameIpa[ch];
    if (letterIpa != null) {
      result.add(letterIpa);
    }
  }
  return result;
}

String _assembleAndFilter(List<String> words) {
  final kept = <String>[];
  var runeCount = 0;

  for (final rawWord in words) {
    final filtered = _filterValidRunes(rawWord).trim();
    if (filtered.isEmpty) {
      continue;
    }

    final wordRunes = filtered.runes.length;
    if (kept.isEmpty) {
      if (wordRunes <= _kMaxKittenIpaRunes) {
        kept.add(filtered);
        runeCount = wordRunes;
      } else {
        final truncated = String.fromCharCodes(
          filtered.runes.take(_kMaxKittenIpaRunes),
        ).trim();
        if (truncated.isNotEmpty) {
          kept.add(truncated);
        }
        break;
      }
    } else {
      final candidateLength = runeCount + 1 + wordRunes;
      if (candidateLength > _kMaxKittenIpaRunes) {
        break;
      }
      kept.add(filtered);
      runeCount = candidateLength;
    }
  }

  return kept.join(' ').trim();
}

String _filterValidRunes(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (kKittenValidTokenCodepoints.contains(rune)) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

String _foldLatinDiacritics(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final replacement = _diacriticFoldMap[rune];
    if (replacement != null) {
      buffer.write(replacement);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Rule-based Anglicized scientific-Latin/Greek G2P converter.
String _phonemizeLatinateWord(String lowerWord) {
  var word = lowerWord;

  // 1. Leading silent Greek clusters and initial x -> z.
  for (final rule in _leadingClusterRules) {
    if (rule.pattern.hasMatch(word)) {
      word = word.replaceFirst(rule.pattern, rule.replacement);
      break;
    }
  }

  // 2. Match longest-first Anglicized taxonomic suffix.
  var stemLength = word.length;
  _SuffixIpaRule? matchedSuffix;
  for (final rule in _taxonomicSuffixRules) {
    if (word.length >= rule.minWordLength && word.endsWith(rule.suffix)) {
      matchedSuffix = rule;
      stemLength = word.length - rule.suffix.length;
      break;
    }
  }

  // 3. If no taxonomic suffix matched, check Anglicized final-syllable endings.
  _EndingIpaRule? matchedEnding;
  if (matchedSuffix == null) {
    for (final rule in _finalEndingRules) {
      if (word.length >= rule.minWordLength && word.endsWith(rule.ending)) {
        matchedEnding = rule;
        stemLength = word.length - rule.ending.length;
        break;
      }
    }
  }

  // 4. Convert stem characters into phoneme tokens, keeping full-word lookahead
  //    for soft c/g and closed-syllable vowel quality.
  final tokens = _convertStemToPhonemes(word, stemLength);

  // Append final-syllable ending tokens (still eligible for Latin stress rule).
  if (matchedEnding != null) {
    tokens.addAll(matchedEnding.tokens);
  }

  // 5. Place primary stress if the suffix does not already supply one.
  final suffixHasStress =
      matchedSuffix != null && matchedSuffix.ipa.contains('ˈ');
  if (!suffixHasStress) {
    _applyPrimaryStress(
      tokens,
      stressLastStemVowel:
          matchedSuffix != null && matchedSuffix.stressLastStemVowel,
    );
  }

  final buffer = StringBuffer();
  for (final token in tokens) {
    buffer.write(token.ipa);
  }
  if (matchedSuffix != null) {
    buffer.write(matchedSuffix.ipa);
  }

  return buffer.toString();
}

List<_PhonemeToken> _convertStemToPhonemes(String fullWord, int stemLength) {
  final tokens = <_PhonemeToken>[];
  var i = 0;

  while (i < stemLength) {
    final remaining = stemLength - i;
    final ch = fullWord[i];

    // 3-character clusters
    if (remaining >= 3) {
      final tri = fullWord.substring(i, i + 3);
      if (tri == 'sch') {
        tokens.add(const _PhonemeToken('ʃ', isVowel: false));
        i += 3;
        continue;
      }
      if (tri == 'aer') {
        tokens.add(const _PhonemeToken('ɛə', isVowel: true, isHeavy: true));
        tokens.add(const _PhonemeToken('ɹ', isVowel: false));
        i += 3;
        continue;
      }
      if (tri == 'tch') {
        tokens.add(const _PhonemeToken('ʧ', isVowel: false));
        i += 3;
        continue;
      }
    }

    // 2-character clusters
    if (remaining >= 2) {
      final di = fullWord.substring(i, i + 2);

      // Consonant digraphs
      if (di == 'ch') {
        tokens.add(const _PhonemeToken('k', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'ph') {
        tokens.add(const _PhonemeToken('f', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'th') {
        tokens.add(const _PhonemeToken('θ', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'rh') {
        tokens.add(const _PhonemeToken('ɹ', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'sh') {
        tokens.add(const _PhonemeToken('ʃ', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'qu') {
        tokens.add(const _PhonemeToken('kw', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'ck') {
        tokens.add(const _PhonemeToken('k', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'gh') {
        tokens.add(const _PhonemeToken('ɡ', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'wh') {
        tokens.add(const _PhonemeToken('w', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'ng') {
        if (_isFrontVowelAt(fullWord, i + 2)) {
          tokens.add(const _PhonemeToken('nʤ', isVowel: false));
        } else {
          tokens.add(const _PhonemeToken('ŋɡ', isVowel: false));
        }
        i += 2;
        continue;
      }
      if (di == 'sc' && _isSofteningContextAt(fullWord, i + 2)) {
        tokens.add(const _PhonemeToken('s', isVowel: false));
        i += 2;
        continue;
      }
      if (di == 'cc' && _isSofteningContextAt(fullWord, i + 2)) {
        tokens.add(const _PhonemeToken('ks', isVowel: false));
        i += 2;
        continue;
      }

      // Vowel digraphs & diphthongs
      if (di == 'ae') {
        tokens.add(const _PhonemeToken('iː', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'oe') {
        final isFinalInWord = (i + 2) >= fullWord.length;
        tokens.add(
          _PhonemeToken(
            isFinalInWord ? 'oʊ' : 'iː',
            isVowel: true,
            isHeavy: true,
          ),
        );
        i += 2;
        continue;
      }
      if (di == 'au') {
        tokens.add(const _PhonemeToken('ɔː', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'eu') {
        final prevIsLiquidOrS =
            tokens.isNotEmpty &&
            (tokens.last.ipa.endsWith('s') ||
                tokens.last.ipa.endsWith('ɹ') ||
                tokens.last.ipa.endsWith('l'));
        tokens.add(
          _PhonemeToken(
            prevIsLiquidOrS ? 'uː' : 'juː',
            isVowel: true,
            isHeavy: true,
          ),
        );
        i += 2;
        continue;
      }
      if (di == 'ou') {
        tokens.add(const _PhonemeToken('uː', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'oi') {
        tokens.add(const _PhonemeToken('ɔɪ', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'ei') {
        tokens.add(const _PhonemeToken('aɪ', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'ee') {
        tokens.add(const _PhonemeToken('iː', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'oo') {
        tokens.add(const _PhonemeToken('uː', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
      if (di == 'ai') {
        tokens.add(const _PhonemeToken('eɪ', isVowel: true, isHeavy: true));
        i += 2;
        continue;
      }
    }

    // Collapse doubled consonants inside the stem (except cc before front vowel
    // which was already handled above).
    if (!_isVowelChar(ch) && i + 1 < stemLength && fullWord[i + 1] == ch) {
      i += 1;
      continue;
    }

    // Single vowels
    if (_isVowelChar(ch)) {
      final isClosed = _isClosedSyllableAfter(fullWord, i);
      final followedByRClosed = _isFollowedByClosedR(fullWord, i);
      final followedByVowel =
          (i + 1) < fullWord.length && _isVowelChar(fullWord[i + 1]);

      final String vowelIpa;
      switch (ch) {
        case 'a':
          vowelIpa = followedByRClosed ? 'ɑː' : 'æ';
        case 'e':
          vowelIpa = followedByRClosed ? 'ɜː' : 'ɛ';
        case 'i':
          if (followedByRClosed) {
            vowelIpa = 'ɜː';
          } else if (followedByVowel) {
            vowelIpa = 'i';
          } else {
            vowelIpa = 'ɪ';
          }
        case 'o':
          if (followedByRClosed) {
            vowelIpa = 'ɔː';
          } else if (isClosed) {
            vowelIpa = 'ɑː';
          } else {
            vowelIpa = 'oʊ';
          }
        case 'u':
          if (followedByRClosed) {
            vowelIpa = 'ɜː';
          } else if (isClosed) {
            vowelIpa = 'ʌ';
          } else {
            vowelIpa = 'uː';
          }
        case 'y':
          if (isClosed) {
            vowelIpa = 'ɪ';
          } else if (i <= 2 || i == stemLength - 1) {
            vowelIpa = 'aɪ';
          } else {
            vowelIpa = 'ɪ';
          }
        default:
          vowelIpa = 'ə';
      }

      tokens.add(
        _PhonemeToken(
          vowelIpa,
          isVowel: true,
          isHeavy: isClosed || followedByRClosed,
        ),
      );
      i += 1;
      continue;
    }

    // Single consonants
    switch (ch) {
      case 'c':
        final soft = _isSofteningContextAt(fullWord, i + 1);
        tokens.add(_PhonemeToken(soft ? 's' : 'k', isVowel: false));
      case 'g':
        final soft = _isFrontVowelAt(fullWord, i + 1);
        tokens.add(_PhonemeToken(soft ? 'ʤ' : 'ɡ', isVowel: false));
      case 'x':
        tokens.add(const _PhonemeToken('ks', isVowel: false));
      case 'r':
        tokens.add(const _PhonemeToken('ɹ', isVowel: false));
      case 'j':
        tokens.add(const _PhonemeToken('ʤ', isVowel: false));
      case 'q':
        tokens.add(const _PhonemeToken('k', isVowel: false));
      case 'b':
      case 'd':
      case 'f':
      case 'h':
      case 'k':
      case 'l':
      case 'm':
      case 'n':
      case 'p':
      case 's':
      case 't':
      case 'v':
      case 'w':
      case 'z':
        tokens.add(_PhonemeToken(ch, isVowel: false));
    }

    i += 1;
  }

  return tokens;
}

void _applyPrimaryStress(
  List<_PhonemeToken> tokens, {
  required bool stressLastStemVowel,
}) {
  final vowelIndices = <int>[];
  for (var idx = 0; idx < tokens.length; idx++) {
    if (tokens[idx].isVowel) {
      vowelIndices.add(idx);
    }
  }

  if (vowelIndices.isEmpty) {
    return;
  }

  final int targetVowelIdx;
  if (stressLastStemVowel) {
    targetVowelIdx = vowelIndices.last;
  } else if (vowelIndices.length == 1) {
    targetVowelIdx = vowelIndices[0];
  } else if (vowelIndices.length == 2) {
    targetVowelIdx = vowelIndices[0];
  } else {
    final penultIdx = vowelIndices[vowelIndices.length - 2];
    final antepenultIdx = vowelIndices[vowelIndices.length - 3];
    targetVowelIdx = tokens[penultIdx].isHeavy ? penultIdx : antepenultIdx;
  }

  final existing = tokens[targetVowelIdx];
  tokens[targetVowelIdx] = _PhonemeToken(
    'ˈ${existing.ipa}',
    isVowel: existing.isVowel,
    isHeavy: existing.isHeavy,
  );
}

bool _isVowelChar(String ch) {
  return ch == 'a' ||
      ch == 'e' ||
      ch == 'i' ||
      ch == 'o' ||
      ch == 'u' ||
      ch == 'y';
}

bool _isFrontVowelAt(String word, int index) {
  if (index >= word.length) {
    return false;
  }
  final next = word[index];
  return next == 'e' || next == 'i' || next == 'y';
}

bool _isSofteningContextAt(String word, int index) {
  if (index >= word.length) {
    return false;
  }
  final next = word[index];
  if (next == 'e' || next == 'i' || next == 'y') {
    return true;
  }
  if (index + 1 < word.length) {
    final pair = word.substring(index, index + 2);
    if (pair == 'ae' || pair == 'oe') {
      return true;
    }
  }
  return false;
}

bool _isFollowedByClosedR(String word, int vowelIndex) {
  final rIdx = vowelIndex + 1;
  if (rIdx >= word.length || word[rIdx] != 'r') {
    return false;
  }
  if (rIdx + 1 >= word.length) {
    return true;
  }
  return !_isVowelChar(word[rIdx + 1]);
}

bool _isClosedSyllableAfter(String word, int vowelIndex) {
  var cursor = vowelIndex + 1;
  if (cursor >= word.length) {
    return false;
  }
  if (_isVowelChar(word[cursor])) {
    return false;
  }

  // Count effective consonant units before the next vowel.
  var units = 0;
  final start = cursor;
  while (cursor < word.length && !_isVowelChar(word[cursor])) {
    if (cursor + 1 < word.length) {
      final pair = word.substring(cursor, cursor + 2);
      if (pair == 'ch' ||
          pair == 'ph' ||
          pair == 'th' ||
          pair == 'sh' ||
          pair == 'rh' ||
          pair == 'qu') {
        units += 1;
        cursor += 2;
        continue;
      }
    }
    if (word[cursor] == 'x') {
      units += 2;
    } else {
      units += 1;
    }
    cursor += 1;
  }

  // Word-final consonant(s) close the syllable.
  if (cursor >= word.length) {
    return units >= 1;
  }

  // Classic muta cum liquida (pl, br, tr, dr, cr, gr, fr, pr, cl, gl, fl, bl)
  // can start the next syllable as an onset cluster, keeping this syllable open.
  if (units == 2 && cursor - start == 2) {
    final cluster = word.substring(start, cursor);
    if (_onsetClusters.contains(cluster)) {
      return false;
    }
  }

  return units >= 2;
}

class _PhonemeToken {
  const _PhonemeToken(this.ipa, {required this.isVowel, this.isHeavy = false});

  final String ipa;
  final bool isVowel;
  final bool isHeavy;
}

class _RegexRule {
  const _RegexRule(this.pattern, this.replacement);

  final RegExp pattern;
  final String replacement;
}

class _SuffixIpaRule {
  const _SuffixIpaRule({
    required this.suffix,
    required this.minWordLength,
    required this.ipa,
    this.stressLastStemVowel = false,
  });

  final String suffix;
  final int minWordLength;
  final String ipa;
  final bool stressLastStemVowel;
}

class _EndingIpaRule {
  const _EndingIpaRule({
    required this.ending,
    required this.minWordLength,
    required this.tokens,
  });

  final String ending;
  final int minWordLength;
  final List<_PhonemeToken> tokens;
}

final RegExp _nonSpokenPunctuationPattern = RegExp(r'''[\[\]'"‘’“”]''');
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _nonAlphanumericPattern = RegExp(r'[^A-Za-z0-9]+');
final RegExp _digitPattern = RegExp(r'[0-9]');

const Set<String> _onsetClusters = {
  'bl',
  'br',
  'cl',
  'cr',
  'dr',
  'fl',
  'fr',
  'gl',
  'gr',
  'pl',
  'pr',
  'tr',
};

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

final List<_RegexRule> _leadingClusterRules = [
  _RegexRule(RegExp(r'^pt(?=[aeiouy])'), 't'),
  _RegexRule(RegExp(r'^ps(?=[aeiouy])'), 's'),
  _RegexRule(RegExp(r'^cn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^ct(?=[aeiouy])'), 't'),
  _RegexRule(RegExp(r'^mn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^pn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^gn(?=[aeiouy])'), 'n'),
  _RegexRule(RegExp(r'^rh(?=[aeiouy])'), 'r'),
  _RegexRule(RegExp(r'^x(?=[aeiouy])'), 'z'),
];

/// Longest-first Anglicized taxonomic suffix rules.
const List<_SuffixIpaRule> _taxonomicSuffixRules = [
  _SuffixIpaRule(suffix: 'mycetes', minWordLength: 9, ipa: 'maɪsˈiːtiːz'),
  _SuffixIpaRule(suffix: 'oideae', minWordLength: 8, ipa: 'ˈɔɪdiːiː'),
  _SuffixIpaRule(suffix: 'mycota', minWordLength: 8, ipa: 'maɪkˈoʊtə'),
  _SuffixIpaRule(suffix: 'saurus', minWordLength: 8, ipa: 'sˈɔːɹəs'),
  _SuffixIpaRule(suffix: 'coccus', minWordLength: 8, ipa: 'kˈɑːkəs'),
  _SuffixIpaRule(suffix: 'bacter', minWordLength: 8, ipa: 'bˈæktɚ'),
  _SuffixIpaRule(suffix: 'aceae', minWordLength: 7, ipa: 'ˈeɪsiːiː'),
  _SuffixIpaRule(suffix: 'monas', minWordLength: 7, ipa: 'mˈoʊnəs'),
  _SuffixIpaRule(suffix: 'opsis', minWordLength: 7, ipa: 'ˈɑːpsɪs'),
  _SuffixIpaRule(suffix: 'ensis', minWordLength: 7, ipa: 'ˈɛnsɪs'),
  _SuffixIpaRule(suffix: 'phyta', minWordLength: 7, ipa: 'fˈaɪtə'),
  _SuffixIpaRule(suffix: 'cetes', minWordLength: 7, ipa: 'sˈiːtiːz'),
  _SuffixIpaRule(
    suffix: 'idae',
    minWordLength: 6,
    ipa: 'ɪdiː',
    stressLastStemVowel: true,
  ),
  _SuffixIpaRule(suffix: 'inae', minWordLength: 6, ipa: 'ˈaɪniː'),
  _SuffixIpaRule(suffix: 'ales', minWordLength: 6, ipa: 'ˈeɪliːz'),
  _SuffixIpaRule(suffix: 'zoa', minWordLength: 5, ipa: 'zˈoʊə'),
  _SuffixIpaRule(
    suffix: 'ii',
    minWordLength: 4,
    ipa: 'iːaɪ',
    stressLastStemVowel: true,
  ),
];

/// Anglicized Latin final-syllable endings when no taxonomic suffix matched.
const List<_EndingIpaRule> _finalEndingRules = [
  _EndingIpaRule(
    ending: 'us',
    minWordLength: 4,
    tokens: [
      _PhonemeToken('ə', isVowel: true),
      _PhonemeToken('s', isVowel: false),
    ],
  ),
  _EndingIpaRule(
    ending: 'um',
    minWordLength: 4,
    tokens: [
      _PhonemeToken('ə', isVowel: true),
      _PhonemeToken('m', isVowel: false),
    ],
  ),
  _EndingIpaRule(
    ending: 'is',
    minWordLength: 4,
    tokens: [
      _PhonemeToken('ɪ', isVowel: true),
      _PhonemeToken('s', isVowel: false),
    ],
  ),
  _EndingIpaRule(
    ending: 'es',
    minWordLength: 4,
    tokens: [
      _PhonemeToken('iː', isVowel: true, isHeavy: true),
      _PhonemeToken('z', isVowel: false),
    ],
  ),
  _EndingIpaRule(
    ending: 'ae',
    minWordLength: 4,
    tokens: [_PhonemeToken('iː', isVowel: true, isHeavy: true)],
  ),
  _EndingIpaRule(
    ending: 'a',
    minWordLength: 3,
    tokens: [_PhonemeToken('ə', isVowel: true)],
  ),
  _EndingIpaRule(
    ending: 'i',
    minWordLength: 3,
    tokens: [_PhonemeToken('aɪ', isVowel: true, isHeavy: true)],
  ),
];

const Map<String, String> _digitIpa = {
  '0': 'zˈiːɹoʊ',
  '1': 'wˈʌn',
  '2': 'tˈuː',
  '3': 'θɹˈiː',
  '4': 'fˈɔːɹ',
  '5': 'fˈaɪv',
  '6': 'sˈɪks',
  '7': 'sˈɛvən',
  '8': 'ˈeɪt',
  '9': 'nˈaɪn',
};

const Map<String, String> _letterNameIpa = {
  'a': 'ˈeɪ',
  'b': 'bˈiː',
  'c': 'sˈiː',
  'd': 'dˈiː',
  'e': 'ˈiː',
  'f': 'ˈɛf',
  'g': 'ʤˈiː',
  'h': 'ˈeɪʧ',
  'i': 'ˈaɪ',
  'j': 'ʤˈeɪ',
  'k': 'kˈeɪ',
  'l': 'ˈɛl',
  'm': 'ˈɛm',
  'n': 'ˈɛn',
  'o': 'ˈoʊ',
  'p': 'pˈiː',
  'q': 'kjˈuː',
  'r': 'ˈɑːɹ',
  's': 'ˈɛs',
  't': 'tˈiː',
  'u': 'jˈuː',
  'v': 'vˈiː',
  'w': 'dˈʌbəljˌuː',
  'x': 'ˈɛks',
  'y': 'wˈaɪ',
  'z': 'zˈiː',
};

const Map<int, String> _diacriticFoldMap = {
  0x00C0: 'A', 0x00C1: 'A', 0x00C2: 'A', 0x00C3: 'A', 0x00C4: 'A', 0x00C5: 'A',
  0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a', 0x00E5: 'a',
  0x00C6: 'AE', 0x00E6: 'ae',
  0x00C7: 'C', 0x00E7: 'c',
  0x00C8: 'E', 0x00C9: 'E', 0x00CA: 'E', 0x00CB: 'E',
  0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
  0x00CC: 'I', 0x00CD: 'I', 0x00CE: 'I', 0x00CF: 'I',
  0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
  0x00D1: 'N', 0x00F1: 'n',
  0x00D2: 'O', 0x00D3: 'O', 0x00D4: 'O', 0x00D5: 'O', 0x00D6: 'O', 0x00D8: 'O',
  0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o', 0x00F6: 'o', 0x00F8: 'o',
  0x0152: 'OE', 0x0153: 'oe',
  0x00D9: 'U', 0x00DA: 'U', 0x00DB: 'U', 0x00DC: 'U',
  0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
  0x00DD: 'Y', 0x00FD: 'y', 0x00FF: 'y',
  0x00DF: 'ss',
};

/// Curated Anglicized KittenTTS IPA dictionary for common NCBI taxonomy
/// descriptors and iconic or irregular biological taxa.
const Map<String, String> _knownWordIpa = {
  // Common NCBI and English taxonomy descriptors
  'root': 'ɹˈuːt',
  'cellular': 'sˈɛljʊlɚ',
  'organism': 'ˈɔːɹɡənˌɪzəm',
  'organisms': 'ˈɔːɹɡənˌɪzəmz',
  'species': 'spˈiːʃiːz',
  'subspecies': 'sˈʌbspiːʃiːz',
  'variety': 'vəɹˈaɪəti',
  'forma': 'fˈɔːɹmə',
  'specialis': 'spˌɛʃiˈeɪlɪs',
  'strain': 'stɹˈeɪn',
  'series': 'sˈɪɹiːz',
  'affinis': 'əfˈaɪnɪs',
  'confer': 'kənfˈɜːɹ',
  'virus': 'vˈaɪɹəs',
  'viruses': 'vˈaɪɹəsɪz',
  'bacteria': 'bæktˈɪɹiə',
  'bacterium': 'bæktˈɪɹiəm',
  'archaea': 'ɑːɹkˈiːə',
  'eukaryota': 'jˌuːkæɹiˈoʊtə',
  'eukaryotes': 'jˌuːkˈæɹiˌoʊts',
  'unclassified': 'ʌnklˈæsɪfˌaɪd',
  'uncultured': 'ʌnkˈʌlʧɚd',
  'environmental': 'ɛnvˌaɪɹənmˈɛntəl',
  'sample': 'sˈæmpəl',
  'samples': 'sˈæmpəlz',
  'other': 'ˈʌðɚ',
  'sequence': 'sˈiːkwəns',
  'sequences': 'sˈiːkwənsɪz',
  'metagenome': 'mˈɛtəʤˌiːnoʊm',
  'group': 'ɡɹˈuːp',
  'complex': 'kˈɑːmplɛks',
  'clade': 'klˈeɪd',
  'hybrid': 'hˈaɪbɹɪd',
  'candidatus': 'kˌændɪdˈeɪtəs',
  'incertae': 'ɪnsˈɜːɹtiː',
  'sedis': 'sˈiːdɪs',
  'synthetic': 'sɪnθˈɛtɪk',
  'construct': 'kˈɑːnstɹʌkt',
  'vector': 'vˈɛktɚ',
  'isolate': 'ˈaɪsəleɪt',
  'serovar': 'sˈɪɹoʊvˌɑːɹ',
  'biovar': 'bˈaɪoʊvˌɑːɹ',
  'pathovar': 'pˈæθoʊvˌɑːɹ',
  'cultivar': 'kˈʌltɪvˌɑːɹ',
  'in': 'ˈɪn',
  'of': 'ˈʌv',
  'and': 'ˈænd',
  'the': 'ðə',

  // Iconic and irregular biological taxa
  'homo': 'hˈoʊmoʊ',
  'sapiens': 'sˈeɪpiɛnz',
  'escherichia': 'ˌɛʃɚˈɪkiə',
  'coli': 'kˈoʊlaɪ',
  'panthera': 'pænθˈɪɹə',
  'leo': 'lˈiːoʊ',
  'tigris': 'tˈaɪɡɹɪs',
  'tyrannosaurus': 'tɪɹˌænəsˈɔːɹəs',
  'rex': 'ɹˈɛks',
  'staphylococcus': 'stˌæfɪloʊkˈɑːkəs',
  'aureus': 'ˈɔːɹiəs',
  'arabidopsis': 'əɹˌæbɪdˈɑːpsɪs',
  'thaliana': 'θˌæliˈɑːnə',
  'drosophila': 'dɹəsˈɑːfɪlə',
  'melanogaster': 'mˌɛlənoʊɡˈæstɚ',
  'caenorhabditis': 'sˌiːnoʊɹæbdˈaɪtɪs',
  'elegans': 'ˈɛlɪɡænz',
  'saccharomyces': 'sˌækəɹoʊmˈaɪsiːz',
  'cerevisiae': 'sˌɛɹɪvˈɪsiiː',
  'mus': 'mˈʌs',
  'musculus': 'mˈʌskjʊləs',
  'danio': 'dˈɑːnioʊ',
  'rerio': 'ɹˈɪɹioʊ',
  'felis': 'fˈiːlɪs',
  'catus': 'kˈætəs',
  'canis': 'kˈeɪnɪs',
  'lupus': 'lˈuːpəs',
  'rattus': 'ɹˈætəs',
  'norvegicus': 'nɔːɹvˈiːʤɪkəs',
  'bos': 'bˈɑːs',
  'taurus': 'tˈɔːɹəs',
  'gallus': 'ɡˈæləs',
  'zea': 'zˈiːə',
  'mays': 'mˈeɪz',
  'oryza': 'əɹˈaɪzə',
  'sativa': 'sətˈiːvə',
  'mycobacterium': 'mˌaɪkoʊbæktˈɪɹiəm',
  'tuberculosis': 'tjuːbˌɜːɹkjʊlˈoʊsɪs',
  'pseudomonas': 'sˌuːdəmˈoʊnəs',
  'aeruginosa': 'ɛəɹˌuːʤɪnˈoʊsə',
  'bacillus': 'bəsˈɪləs',
  'subtilis': 'sˈʌbtɪlɪs',
  'clostridium': 'klɑːstɹˈɪdiəm',
  'difficile': 'dˌɪfɪsˈiːl',
  'plasmodium': 'plæzmˈoʊdiəm',
  'falciparum': 'fælsˈɪpəɹəm',
  'aedes': 'iːˈiːdiːz',
  'aegypti': 'ɪʤˈɪptaɪ',
  'anopheles': 'ənˈɑːfəliːz',
  'gambiae': 'ɡˈæmbiiː',
  'xenopus': 'zˈɛnəpəs',
  'laevis': 'lˈiːvɪs',
  'cnidaria': 'naɪdˈɛɹiə',
  'ctenophora': 'tɪnˈɑːfəɹə',
  'chordata': 'kɔːɹdˈɑːtə',
  'echinodermata': 'ɪkˌaɪnoʊdˈɜːɹmətə',
  'arthropoda': 'ɑːɹθɹˈɑːpədə',
  'mollusca': 'məlˈʌskə',
  'mammalia': 'məmˈeɪliə',
  'aves': 'ˈeɪviːz',
  'reptilia': 'ɹɛptˈɪliə',
  'amphibia': 'æmfˈɪbiə',
  'insecta': 'ɪnsˈɛktə',
  'arachnida': 'əɹˈæknɪdə',
  'plantae': 'plˈæntiː',
  'fungi': 'fˈʌnʤaɪ',
  'animalia': 'ˌænɪmˈeɪliə',
  'aloe': 'ˈæloʊ',
  'vera': 'vˈɪɹə',
  'ginkgo': 'ɡˈɪŋkoʊ',
  'biloba': 'baɪlˈoʊbə',
  'fuchsia': 'fjˈuːʃə',
  'sequoia': 'sɪkwˈɔɪə',
  'eucalyptus': 'jˌuːkəlˈɪptəs',
  'chrysanthemum': 'kɹɪsˈænθəməm',
  'pterodactylus': 'tˌɛɹədˈæktɪləs',
  'archaeopteryx': 'ˌɑːɹkiˈɑːptəɹɪks',
  'coelacanth': 'sˈiːləkænθ',
  'amoeba': 'əmˈiːbə',
};
