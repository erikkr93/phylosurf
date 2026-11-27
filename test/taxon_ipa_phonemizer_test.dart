import 'package:flutter_test/flutter_test.dart';
import 'package:ncbi_taxonomy_explorer/utils/taxon_ipa_phonemizer.dart';

void _expectValidKittenIpa(String ipa) {
  expect(ipa.runes.length, lessThanOrEqualTo(380));
  for (final rune in ipa.runes) {
    expect(
      kKittenValidTokenCodepoints.contains(rune),
      isTrue,
      reason:
          'Unexpected rune U+${rune.toRadixString(16).toUpperCase()} '
          '("${String.fromCharCode(rune)}") in "$ipa"',
    );
  }
}

void main() {
  group('phonemizeScientificNameToKittenIpa', () {
    test('returns empty string and empty codepoints for blank or '
        'unpronounceable inputs', () {
      const blankInputs = [
        '',
        '   \t\n  ',
        '[ ]',
        "''",
        '""',
        '‘’“”',
        '... --- !?',
        '()',
        '🧬🦠',
      ];

      for (final input in blankInputs) {
        expect(phonemizeScientificNameToKittenIpa(input), '');
        expect(phonemizeScientificNameToKittenCodepoints(input), isEmpty);
      }
    });

    test('produces curated KittenTTS IPA for iconic species and NCBI '
        'descriptors', () {
      final cases = <String, String>{
        'Homo sapiens': 'hˈoʊmoʊ sˈeɪpiɛnz',
        'Escherichia coli': 'ˌɛʃɚˈɪkiə kˈoʊlaɪ',
        'root': 'ɹˈuːt',
        'cellular organisms': 'sˈɛljʊlɚ ˈɔːɹɡənˌɪzəmz',
        'Archaea': 'ɑːɹkˈiːə',
        'Eukaryota': 'jˌuːkæɹiˈoʊtə',
        'Panthera leo': 'pænθˈɪɹə lˈiːoʊ',
        'Tyrannosaurus rex': 'tɪɹˌænəsˈɔːɹəs ɹˈɛks',
        'Staphylococcus aureus': 'stˌæfɪloʊkˈɑːkəs ˈɔːɹiəs',
        'Caenorhabditis elegans': 'sˌiːnoʊɹæbdˈaɪtɪs ˈɛlɪɡænz',
        'Saccharomyces cerevisiae': 'sˌækəɹoʊmˈaɪsiːz sˌɛɹɪvˈɪsiiː',
        'unclassified Bacteria': 'ʌnklˈæsɪfˌaɪd bæktˈɪɹiə',
        'incertae sedis': 'ɪnsˈɜːɹtiː sˈiːdɪs',
        'Aloe vera': 'ˈæloʊ vˈɪɹə',
        'Ginkgo biloba': 'ɡˈɪŋkoʊ baɪlˈoʊbə',
        'Cnidaria': 'naɪdˈɛɹiə',
        'Ctenophora': 'tɪnˈɑːfəɹə',
      };

      for (final entry in cases.entries) {
        final ipa = phonemizeScientificNameToKittenIpa(entry.key);
        expect(ipa, entry.value, reason: 'Input: ${entry.key}');
        _expectValidKittenIpa(ipa);
        expect(
          phonemizeScientificNameToKittenCodepoints(entry.key),
          ipa.runes.toList(),
        );
      }
    });

    test('handles brackets, quotes, and rank/nomenclature abbreviations', () {
      expect(
        phonemizeScientificNameToKittenIpa('[Clostridium] difficile'),
        'klɑːstɹˈɪdiəm dˌɪfɪsˈiːl',
      );
      expect(
        phonemizeScientificNameToKittenIpa(
          'Mycobacterium tuberculosis subsp. tuberculosis',
        ),
        'mˌaɪkoʊbæktˈɪɹiəm tjuːbˌɜːɹkjʊlˈoʊsɪs sˈʌbspiːʃiːz tjuːbˌɜːɹkjʊlˈoʊsɪs',
      );
      expect(
        phonemizeScientificNameToKittenIpa('Canis lupus ssp. familiaris'),
        startsWith('kˈeɪnɪs lˈuːpəs sˈʌbspiːʃiːz '),
      );
      expect(
        phonemizeScientificNameToKittenIpa('Puccinia graminis f. sp. tritici'),
        contains('fˈɔːɹmə spˌɛʃiˈeɪlɪs'),
      );
      expect(
        phonemizeScientificNameToKittenIpa('Brassica oleracea var. italica'),
        contains('vəɹˈaɪəti'),
      );
      expect(
        phonemizeScientificNameToKittenIpa('Homo aff. sapiens'),
        'hˈoʊmoʊ əfˈaɪnɪs sˈeɪpiɛnz',
      );
      expect(
        phonemizeScientificNameToKittenIpa('Homo cf. sapiens'),
        'hˈoʊmoʊ kənfˈɜːɹ sˈeɪpiɛnz',
      );
      expect(
        phonemizeScientificNameToKittenIpa('Solanum ser. Tuberosa'),
        contains('sˈɪɹiːz'),
      );
      expect(
        phonemizeScientificNameToKittenIpa('Escherichia coli str. K-12'),
        'ˌɛʃɚˈɪkiə kˈoʊlaɪ stɹˈeɪn kˈeɪ wˈʌn tˈuː',
      );
    });

    test('pronounces alphanumeric strain and code tokens via letter names '
        'and digits', () {
      expect(
        phonemizeScientificNameToKittenIpa('Escherichia coli K-12'),
        'ˌɛʃɚˈɪkiə kˈoʊlaɪ kˈeɪ wˈʌn tˈuː',
      );
      expect(
        phonemizeScientificNameToKittenIpa('Bacillus sp. 123'),
        'bəsˈɪləs spˈiːʃiːz wˈʌn tˈuː θɹˈiː',
      );
      expect(
        phonemizeScientificNameToKittenIpa('H1N1'),
        'ˈeɪʧ wˈʌn ˈɛn wˈʌn',
      );
      expect(
        phonemizeScientificNameToKittenIpa('O157:H7'),
        'ˈoʊ wˈʌn fˈaɪv sˈɛvən ˈeɪʧ sˈɛvən',
      );
      expect(
        phonemizeScientificNameToKittenIpa('0123456789'),
        'zˈiːɹoʊ wˈʌn tˈuː θɹˈiː fˈɔːɹ fˈaɪv sˈɪks sˈɛvən ˈeɪt nˈaɪn',
      );
    });

    test('phonemizes unknown and synthetic Latinate and Greek taxa with '
        'Anglicized rules and stress', () {
      final rosaceae = phonemizeScientificNameToKittenIpa('Rosaceae');
      expect(rosaceae, endsWith('ˈeɪsiːiː'));
      expect(rosaceae, startsWith('ɹ'));
      _expectValidKittenIpa(rosaceae);

      final hominidae = phonemizeScientificNameToKittenIpa('Hominidae');
      expect(hominidae, endsWith('ɪdiː'));
      expect(hominidae, contains('ˈ'));
      _expectValidKittenIpa(hominidae);

      final homininae = phonemizeScientificNameToKittenIpa('Homininae');
      expect(homininae, endsWith('ˈaɪniː'));
      _expectValidKittenIpa(homininae);

      final bacillales = phonemizeScientificNameToKittenIpa('Bacillales');
      expect(bacillales, endsWith('ˈeɪliːz'));
      expect(bacillales, contains('s'));
      _expectValidKittenIpa(bacillales);

      final pteridium = phonemizeScientificNameToKittenIpa(
        'Pteridium aquilinum',
      );
      expect(pteridium, startsWith('t'));
      expect(pteridium, contains('kw'));
      expect(pteridium, endsWith('əm'));
      _expectValidKittenIpa(pteridium);

      final cnidoblastus = phonemizeScientificNameToKittenIpa('Cnidoblastus');
      expect(cnidoblastus, startsWith('n'));
      expect(cnidoblastus, endsWith('əs'));
      expect(cnidoblastus, contains('ˈ'));
      _expectValidKittenIpa(cnidoblastus);

      final ctenomyidae = phonemizeScientificNameToKittenIpa('Ctenomyidae');
      expect(ctenomyidae, startsWith('t'));
      expect(ctenomyidae, endsWith('ɪdiː'));
      expect(ctenomyidae, contains('ˈ'));
      _expectValidKittenIpa(ctenomyidae);

      final rhodophyta = phonemizeScientificNameToKittenIpa('Rhodophyta');
      expect(rhodophyta, startsWith('ɹ'));
      expect(rhodophyta, endsWith('fˈaɪtə'));
      _expectValidKittenIpa(rhodophyta);

      final staphylococcaceae = phonemizeScientificNameToKittenIpa(
        'Staphylococcaceae',
      );
      expect(staphylococcaceae, contains('f'));
      expect(staphylococcaceae, endsWith('kˈeɪsiːiː'));
      _expectValidKittenIpa(staphylococcaceae);

      final aeromonas = phonemizeScientificNameToKittenIpa(
        'Aeromonas hydrophila',
      );
      expect(aeromonas, startsWith('ɛəɹ'));
      expect(aeromonas, contains('mˈoʊnəs'));
      expect(aeromonas, endsWith('ə'));
      _expectValidKittenIpa(aeromonas);
    });

    test('validates all outputs across diverse scientific names and enforces '
        '380-rune cap', () {
      const diverseNames = [
        'Rosaceae',
        'Rosoideae',
        'Hominidae',
        'Homininae',
        'Bacillales',
        'Ascomycetes',
        'Basidiomycota',
        'Pteridium aquilinum',
        'Cnidoblastus',
        'Ctenomyidae',
        'Rhodophyta',
        'Staphylococcaceae',
        'Aeromonas hydrophila',
        'Mycobacterium tuberculosis subsp. tuberculosis',
        '[Clostridium] difficile',
        'Escherichia coli K-12',
        'Bacillus sp. 123',
        'Xanthomonas oryzae pv. oryzae',
        'Archaeoglobaceae',
        'Orchidaceae',
        'Protozoa',
        'Pterodactylus',
        'Mnemiopsis leidyi',
        'Pneumocystis jirovecii',
        'Gnathostomata',
        'Schistosoma mansoni',
      ];

      for (final name in diverseNames) {
        final ipa = phonemizeScientificNameToKittenIpa(name);
        expect(ipa, isNotEmpty, reason: 'Expected non-empty IPA for "$name"');
        expect(ipa, ipa.trim());
        _expectValidKittenIpa(ipa);
      }

      // Excessively long multi-word input truncates cleanly at word boundary.
      final longName = List.filled(
        60,
        'Staphylococcaceae Mycobacterium',
      ).join(' ');
      final truncated = phonemizeScientificNameToKittenIpa(longName);
      expect(truncated, isNotEmpty);
      expect(truncated.runes.length, lessThanOrEqualTo(380));
      expect(truncated, truncated.trim());
      expect(truncated.endsWith(' '), isFalse);
      _expectValidKittenIpa(truncated);

      // Excessively long single word still respects 380-rune hard cap.
      final singleGiantWord = 'a' * 500;
      final truncatedWord = phonemizeScientificNameToKittenIpa(singleGiantWord);
      expect(truncatedWord.runes.length, lessThanOrEqualTo(380));
      _expectValidKittenIpa(truncatedWord);
    });
  });
}
