import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ncbi_taxonomy_explorer/data/models.dart';
import 'package:ncbi_taxonomy_explorer/data/taxonomy_database.dart';
import 'package:ncbi_taxonomy_explorer/main.dart';
import 'package:ncbi_taxonomy_explorer/services/taxon_speech_service.dart';
import 'package:ncbi_taxonomy_explorer/state/taxonomy_controller.dart';
import 'package:ncbi_taxonomy_explorer/utils/external_links.dart';

class _FakeTaxonSpeechService extends TaxonSpeechService {
  final List<String> spoken = [];
  int stopCalls = 0;
  bool _isSpeaking = false;
  bool _isPreparing = false;
  double? _preparationProgress;
  String? _statusMessage;
  String? _activeScientificName;
  String? _lastError;
  bool shouldSucceed = true;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  bool get isPreparing => _isPreparing;

  @override
  double? get preparationProgress => _preparationProgress;

  @override
  String? get statusMessage => _statusMessage;

  @override
  String? get activeScientificName => _activeScientificName;

  @override
  String? get lastError => _lastError;

  void setPreparingState({
    required String scientificName,
    double? progress,
    String? message,
  }) {
    _isPreparing = true;
    _isSpeaking = false;
    _activeScientificName = scientificName;
    _preparationProgress = progress;
    _statusMessage = message;
    notifyListeners();
  }

  @override
  Future<bool> speakScientificName(String scientificName) async {
    spoken.add(scientificName);
    if (!shouldSucceed) {
      _lastError = 'TTS engine unavailable';
      _isSpeaking = false;
      _isPreparing = false;
      _activeScientificName = null;
      notifyListeners();
      return false;
    }
    _lastError = null;
    _isPreparing = false;
    _preparationProgress = null;
    _statusMessage = null;
    _isSpeaking = true;
    _activeScientificName = scientificName;
    notifyListeners();
    return true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _isSpeaking = false;
    _isPreparing = false;
    _preparationProgress = null;
    _statusMessage = null;
    _activeScientificName = null;
    notifyListeners();
  }
}

void main() {
  testWidgets('NcbiTaxonomyApp renders tree, fuzzy search, and inspector',
      (WidgetTester tester) async {
    final repo = TaxonomyRepository.openInMemory();
    TaxonomyRepository.populateFromLines(
      db: repo.db,
      nodesLines: const [
        '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '131567\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '9606\t|\t131567\t|\tspecies\t|\t\t|\t0\t|',
      ],
      namesLines: const [
        '1\t|\troot\t|\t\t|\tscientific name\t|',
        '131567\t|\tcellular organisms\t|\t\t|\tscientific name\t|',
        '9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|',
        '9606\t|\thuman\t|\t\t|\tgenbank common name\t|',
      ],
    );

    final controller = TaxonomyController(repository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NcbiTaxonomyApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('PhyloSurf'), findsOneWidget);
    expect(find.text('3 taxa'), findsOneWidget);
    expect(find.text('TAXONOMIC TREE'), findsOneWidget);
    expect(controller.hideNonSpecific, isTrue);
    expect(controller.hideSubspecies, isTrue);
    expect(find.text('Hide non-specific'), findsOneWidget);
    expect(find.text('Hide subspecies'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Homo sapens');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Homo sapiens'), findsWidgets);

    await tester.tap(find.text('Reveal').first);
    await tester.pumpAndSettle();

    expect(find.text('human'), findsOneWidget);
    expect(find.text('NCBI TaxID: 9606 • 0 direct child(ren)'), findsOneWidget);

    // Tap a tree row to focus the tree, then test arrow-key navigation.
    await tester.tap(find.text('root').first);
    await tester.pumpAndSettle();
    expect(controller.selectedTaxId, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.selectedTaxId, 131567);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(controller.selectedTaxId, 1);

    // Test Back and Forward history buttons (history is [1 -> 9606 -> 1 -> 131567 -> 1]).
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(controller.selectedTaxId, 131567);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(controller.selectedTaxId, 1);
  });

  testWidgets('Phone viewport (360x780) renders AppBar and tabs without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = TaxonomyRepository.openInMemory();
    TaxonomyRepository.populateFromLines(
      db: repo.db,
      nodesLines: const [
        '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '131567\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '9606\t|\t131567\t|\tspecies\t|\t\t|\t0\t|',
      ],
      namesLines: const [
        '1\t|\troot\t|\t\t|\tscientific name\t|',
        '131567\t|\tcellular organisms\t|\t\t|\tscientific name\t|',
        '9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|',
        '9606\t|\thuman\t|\t\t|\tgenbank common name\t|',
      ],
    );

    final controller = TaxonomyController(repository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NcbiTaxonomyApp(controller: controller));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('3 taxa'), findsOneWidget);
    expect(find.text('Inspect'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'Homo');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Homo sapiens'), findsOneWidget);
  });

  testWidgets('Search Google and Ask Gemini launch expected URLs',
      (WidgetTester tester) async {
    final launched = <Uri>[];
    final repo = TaxonomyRepository.openInMemory();
    TaxonomyRepository.populateFromLines(
      db: repo.db,
      nodesLines: const [
        '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '9606\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
      ],
      namesLines: const [
        '1\t|\troot\t|\t\t|\tscientific name\t|',
        '9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|',
      ],
    );

    final controller = TaxonomyController(repository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      NcbiTaxonomyApp(
        controller: controller,
        uriLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    controller.selectTaxon(9606);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Search Google'));
    await tester.tap(find.text('Search Google'));
    await tester.pumpAndSettle();

    expect(launched.length, 1);
    expect(launched.first.host, 'www.google.com');
    expect(launched.first.queryParameters['q'], 'Homo sapiens');

    await tester.ensureVisible(find.text('Ask Gemini'));
    await tester.tap(find.text('Ask Gemini'));
    await tester.pumpAndSettle();

    expect(launched.length, 2);
    expect(launched[1].toString(), 'https://gemini.google.com/app');

    await tester.ensureVisible(find.text('NCBI Taxonomy'));
    await tester.tap(find.text('NCBI Taxonomy'));
    await tester.pumpAndSettle();

    expect(launched.length, 3);
    expect(
      launched[2].toString(),
      'https://www.ncbi.nlm.nih.gov/datasets/taxonomy/9606/',
    );

    const sample = TaxonNode(
      taxId: 9606,
      parentTaxId: 9605,
      rank: 'species',
      scientificName: 'Homo sapiens',
      childCount: 0,
    );
    expect(
      buildGeminiSummaryPrompt(sample),
      contains('species taxon Homo sapiens (NCBI TaxID: 9606)'),
    );
  });

  testWidgets('Inspector displays total and hidden child counts',
      (WidgetTester tester) async {
    final repo = TaxonomyRepository.openInMemory();
    TaxonomyRepository.populateFromLines(
      db: repo.db,
      nodesLines: const [
        '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '561\t|\t1\t|\tgenus\t|\t\t|\t0\t|',
        '562\t|\t561\t|\tspecies\t|\t\t|\t0\t|',
        '563\t|\t561\t|\tspecies\t|\t\t|\t0\t|',
        '83333\t|\t562\t|\tstrain\t|\t\t|\t0\t|',
      ],
      namesLines: const [
        '1\t|\troot\t|\t\t|\tscientific name\t|',
        '561\t|\tEscherichia\t|\t\t|\tscientific name\t|',
        '562\t|\tEscherichia coli\t|\t\t|\tscientific name\t|',
        '563\t|\tEscherichia sp. 123\t|\t\t|\tscientific name\t|',
        '83333\t|\tEscherichia coli K-12\t|\t\t|\tscientific name\t|',
      ],
    );

    final controller = TaxonomyController(repository: repo);
    addTearDown(controller.dispose);

    await tester.pumpWidget(NcbiTaxonomyApp(controller: controller));
    await tester.pumpAndSettle();

    controller.selectTaxon(561);
    await tester.pumpAndSettle();
    expect(
      find.text('NCBI TaxID: 561 • 2 direct child(ren) (1 hidden)'),
      findsOneWidget,
    );
    expect(find.text('Direct Children (1 of 2, 1 hidden)'), findsOneWidget);

    controller.selectTaxon(562);
    await tester.pumpAndSettle();
    expect(
      find.text('NCBI TaxID: 562 • 1 direct child(ren) (1 hidden)'),
      findsOneWidget,
    );
  });

  testWidgets('Taxon page speak icon pronounces, toggles stop, and stops on navigation',
      (WidgetTester tester) async {
    final repo = TaxonomyRepository.openInMemory();
    TaxonomyRepository.populateFromLines(
      db: repo.db,
      nodesLines: const [
        '1\t|\t1\t|\tno rank\t|\t\t|\t8\t|',
        '9606\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
        '9685\t|\t1\t|\tspecies\t|\t\t|\t0\t|',
      ],
      namesLines: const [
        '1\t|\troot\t|\t\t|\tscientific name\t|',
        '9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|',
        '9685\t|\tFelis catus\t|\t\t|\tscientific name\t|',
      ],
    );

    final controller = TaxonomyController(repository: repo);
    final speechService = _FakeTaxonSpeechService();
    addTearDown(controller.dispose);
    addTearDown(speechService.dispose);

    await tester.pumpWidget(
      NcbiTaxonomyApp(
        controller: controller,
        speechService: speechService,
      ),
    );
    await tester.pumpAndSettle();

    controller.selectTaxon(9606);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();

    expect(speechService.spoken, ['Homo sapiens']);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    // Tapping again stops pronunciation.
    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pumpAndSettle();

    expect(speechService.stopCalls, 1);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

    // Start speaking again, then switch taxon -> should automatically stop.
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();
    expect(speechService.isSpeaking, isTrue);

    controller.selectTaxon(9685);
    await tester.pumpAndSettle();

    expect(speechService.stopCalls, 2);
    expect(speechService.isSpeaking, isFalse);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

    // Preparing state shows a progress indicator and tapping cancels it.
    speechService.setPreparingState(
      scientificName: 'Felis catus',
      progress: 0.4,
      message: 'Downloading KittenTTS Nano...',
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pump();
    expect(speechService.stopCalls, 3);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
  });
}
