import 'package:flutter_test/flutter_test.dart';
import 'package:ncbi_taxonomy_explorer/utils/taxon_pronunciation.dart';

void main() {
  group('formatScientificNameForAnglicizedTts', () {
    test('handles empty, blank, and punctuation-only inputs', () {
      expect(formatScientificNameForAnglicizedTts(''), '');
      expect(formatScientificNameForAnglicizedTts('   \t\n  '), '');
      expect(formatScientificNameForAnglicizedTts('[ ]'), '');
      expect(formatScientificNameForAnglicizedTts("''"), '');
      expect(
        formatScientificNameForAnglicizedTts('  Homo   sapiens  '),
        'Homo sapiens',
      );
    });

    test('strips surrounding and inline non-spoken brackets and quotes', () {
      expect(
        formatScientificNameForAnglicizedTts('[Clostridium] difficile'),
        'Clostridium difficile',
      );
      expect(
        formatScientificNameForAnglicizedTts("'Candidatus Pelagibacter'"),
        'Candidatus Pelagibacter',
      );
      expect(
        formatScientificNameForAnglicizedTts('"Bacillus" subtilis'),
        'Bacillus subtilis',
      );
      expect(
        formatScientificNameForAnglicizedTts('‘Candidatus Liberibacter’'),
        'Candidatus Liberibacter',
      );
    });

    test('expands taxonomic rank and nomenclature abbreviations', () {
      expect(
        formatScientificNameForAnglicizedTts(
          'Puccinia graminis f. sp. tritici',
        ),
        'Puccinia graminis forma specialis tritici',
      );
      expect(
        formatScientificNameForAnglicizedTts(
          'Puccinia graminis F. SP. tritici',
        ),
        'Puccinia graminis forma specialis tritici',
      );
      expect(
        formatScientificNameForAnglicizedTts(
          'Mycobacterium tuberculosis subsp. tuberculosis',
        ),
        'Mycobacterium tuberculosis subspecies tuberculosis',
      );
      expect(
        formatScientificNameForAnglicizedTts('Canis lupus ssp. familiaris'),
        'Canis lupus subspecies familiaris',
      );
      expect(
        formatScientificNameForAnglicizedTts('Brassica oleracea var. italica'),
        'Brassica oleracea variety italica',
      );
      expect(
        formatScientificNameForAnglicizedTts('Pinus nigra f. austriaca'),
        'Pinus nigra forma austriaca',
      );
      expect(
        formatScientificNameForAnglicizedTts('Bacillus sp. 123'),
        'Bacillus species 123',
      );
      expect(
        formatScientificNameForAnglicizedTts('Bacillus spp.'),
        'Bacillus species',
      );
      expect(
        formatScientificNameForAnglicizedTts('Homo aff. sapiens'),
        'Homo affinis sapiens',
      );
      expect(
        formatScientificNameForAnglicizedTts('Homo cf. sapiens'),
        'Homo confer sapiens',
      );
      expect(
        formatScientificNameForAnglicizedTts('Solanum ser. Tuberosa'),
        'Solanum series Tuberosa',
      );
      expect(
        formatScientificNameForAnglicizedTts('Escherichia coli str. K-12'),
        'Escherikia coli strain K-12',
      );
    });

    test('simplifies leading silent Greek consonant clusters', () {
      expect(
        formatScientificNameForAnglicizedTts('Pterodactylus'),
        'Terodactylus',
      );
      expect(
        formatScientificNameForAnglicizedTts('Pseudomonas'),
        'Seudomonas',
      );
      expect(formatScientificNameForAnglicizedTts('Cnidaria'), 'Nidaria');
      expect(formatScientificNameForAnglicizedTts('Ctenophora'), 'Tenophora');
      expect(formatScientificNameForAnglicizedTts('Mnemiopsis'), 'Nemiopsis');
      expect(
        formatScientificNameForAnglicizedTts('Pneumocystis'),
        'Neumocystis',
      );
      expect(
        formatScientificNameForAnglicizedTts('Gnathostomata'),
        'Nathostomata',
      );
      expect(
        formatScientificNameForAnglicizedTts('pterocarpus'),
        'terocarpus',
      );
    });

    test('transforms common Anglicized taxonomic suffixes', () {
      expect(formatScientificNameForAnglicizedTts('Rosaceae'), 'Rosay-see-ee');
      expect(formatScientificNameForAnglicizedTts('Rosoideae'), 'Rosoy-dee-ee');
      expect(formatScientificNameForAnglicizedTts('Hominidae'), 'Hominih-dee');
      expect(formatScientificNameForAnglicizedTts('Homininae'), 'Homineye-nee');
      expect(
        formatScientificNameForAnglicizedTts('Bacillales'),
        'Bacillay-leez',
      );
      expect(
        formatScientificNameForAnglicizedTts('Ascomycetes'),
        'Ascomysee-teez',
      );
      expect(formatScientificNameForAnglicizedTts('darwinii'), 'darwinee-eye');
    });

    test('respects minimum word lengths for suffix rules', () {
      expect(formatScientificNameForAnglicizedTts('ii'), 'ii');
      expect(formatScientificNameForAnglicizedTts('ales'), 'ales');
      expect(formatScientificNameForAnglicizedTts('cetes'), 'cetes');
    });

    test('applies digraph rules without corrupting sch, aer, Aloe, or suffixes',
        () {
      expect(formatScientificNameForAnglicizedTts('Chordata'), 'Kordata');
      expect(
        formatScientificNameForAnglicizedTts('Echinodermata'),
        'Ekinodermata',
      );
      expect(formatScientificNameForAnglicizedTts('Escherichia'), 'Escherikia');
      expect(formatScientificNameForAnglicizedTts('Aedes'), 'Eedes');
      expect(formatScientificNameForAnglicizedTts('Archaea'), 'Arkeea');
      expect(
        formatScientificNameForAnglicizedTts('Caenorhabditis'),
        'Ceenorhabditis',
      );
      expect(formatScientificNameForAnglicizedTts('Aeromonas'), 'Aeromonas');
      expect(formatScientificNameForAnglicizedTts('Coelacanth'), 'Ceelacanth');
      expect(formatScientificNameForAnglicizedTts('Amoeba'), 'Ameeba');
      expect(formatScientificNameForAnglicizedTts('Aloe vera'), 'Aloe vera');
      expect(
        formatScientificNameForAnglicizedTts('Orchidaceae'),
        'Orkiday-see-ee',
      );
      expect(
        formatScientificNameForAnglicizedTts('Pteridaceae'),
        'Teriday-see-ee',
      );
      expect(
        formatScientificNameForAnglicizedTts('Archaeoglobaceae'),
        'Arkeeoglobay-see-ee',
      );
    });

    test('preserves well-known names, strain identifiers, and NCBI descriptors',
        () {
      expect(
        formatScientificNameForAnglicizedTts('Homo sapiens'),
        'Homo sapiens',
      );
      expect(
        formatScientificNameForAnglicizedTts('Panthera leo'),
        'Panthera leo',
      );
      expect(
        formatScientificNameForAnglicizedTts('Escherichia coli'),
        'Escherikia coli',
      );
      expect(
        formatScientificNameForAnglicizedTts('Escherichia coli K-12'),
        'Escherikia coli K-12',
      );
      expect(formatScientificNameForAnglicizedTts('root'), 'root');
      expect(
        formatScientificNameForAnglicizedTts('cellular organisms'),
        'cellular organisms',
      );
      expect(
        formatScientificNameForAnglicizedTts('incertae sedis'),
        'incertae sedis',
      );
      expect(
        formatScientificNameForAnglicizedTts('unclassified Bacteria'),
        'unclassified Bacteria',
      );
      expect(
        formatScientificNameForAnglicizedTts('environmental samples'),
        'environmental samples',
      );
    });
  });
}
