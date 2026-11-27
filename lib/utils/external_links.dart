import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';

Uri buildGoogleSearchUri(String scientificName) {
  return Uri.https('www.google.com', '/search', {'q': scientificName.trim()});
}

Uri buildNcbiTaxonomyUri(int taxId) {
  return Uri.https('www.ncbi.nlm.nih.gov', '/datasets/taxonomy/$taxId/');
}

String buildGeminiSummaryPrompt(TaxonNode taxon) {
  final rankPart = taxon.rank != 'no rank' ? '${taxon.rank} ' : '';
  return 'Summarize the main facts about the ${rankPart}taxon '
      '${taxon.scientificName} (NCBI TaxID: ${taxon.taxId}), including its '
      'key characteristics, habitat/ecology, and biological significance.';
}

Uri buildGeminiUri() {
  return Uri.https('gemini.google.com', '/app');
}

Future<bool> openExternalUri(
  Uri uri, {
  Future<bool> Function(Uri uri)? launcher,
}) async {
  if (launcher != null) {
    return launcher(uri);
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
