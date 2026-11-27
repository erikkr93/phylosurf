import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data/models.dart';
import 'state/taxonomy_controller.dart';
import 'utils/external_links.dart';

void main() {
  runApp(const NcbiTaxonomyApp());
}

class NcbiTaxonomyApp extends StatelessWidget {
  const NcbiTaxonomyApp({
    super.key,
    this.controller,
    this.uriLauncher,
  });

  final TaxonomyController? controller;
  final Future<bool> Function(Uri uri)? uriLauncher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhyloSurf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2DD4BF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: TaxonomyHomePage(
        controller: controller,
        uriLauncher: uriLauncher,
      ),
    );
  }
}

class TaxonomyHomePage extends StatefulWidget {
  const TaxonomyHomePage({
    super.key,
    this.controller,
    this.uriLauncher,
  });

  final TaxonomyController? controller;
  final Future<bool> Function(Uri uri)? uriLauncher;

  @override
  State<TaxonomyHomePage> createState() => _TaxonomyHomePageState();
}

class _TaxonomyHomePageState extends State<TaxonomyHomePage> {
  static const double _treeRowExtent = 28.0;
  static const double _treeIndent = 10.0;

  late final TaxonomyController _controller;
  late final bool _ownsController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _treeFocusNode = FocusNode(debugLabel: 'TaxonomyTree');
  final ScrollController _treeScrollController = ScrollController();
  final ScrollController _treeHorizontalScrollController = ScrollController();
  final FocusNode _inspectorFocusNode = FocusNode(debugLabel: 'TaxonomyInspector');
  final ScrollController _inspectorScrollController = ScrollController();
  bool _compactImport = false;
  int _mobileTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TaxonomyController();
    _controller.addListener(_onControllerChanged);
    _controller.init();
  }

  void _onControllerChanged() {
    if (_controller.query.isEmpty && _searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _searchController.dispose();
    _treeFocusNode.dispose();
    _treeScrollController.dispose();
    _treeHorizontalScrollController.dispose();
    _inspectorFocusNode.dispose();
    _inspectorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _controller.status;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isCompact ? 4 : null,
        title: Row(
          mainAxisSize: isCompact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (_controller.hasDatabase) ...[
              IconButton(
                tooltip: 'Back',
                visualDensity: isCompact ? VisualDensity.compact : null,
                icon: const Icon(Icons.arrow_back),
                onPressed: _controller.canGoBack
                    ? () {
                        final taxId = _controller.goBack();
                        if (taxId != null) _scrollTreeToTaxon(taxId);
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Forward',
                visualDensity: isCompact ? VisualDensity.compact : null,
                icon: const Icon(Icons.arrow_forward),
                onPressed: _controller.canGoForward
                    ? () {
                        final taxId = _controller.goForward();
                        if (taxId != null) _scrollTreeToTaxon(taxId);
                      }
                    : null,
              ),
              SizedBox(width: isCompact ? 4 : 6),
            ],
            if (!isCompact) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/icon/phylosurf_icon.png',
                  width: 28,
                  height: 28,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              fit: isCompact ? FlexFit.tight : FlexFit.loose,
              child: Text(
                'PhyloSurf',
                overflow: TextOverflow.ellipsis,
                style: isCompact ? theme.textTheme.titleMedium : null,
              ),
            ),
            if (!isCompact && _controller.hasDatabase && status != null) ...[
              const SizedBox(width: 10),
              Chip(
                label: Text('${_formatCount(status.nodeCount)} taxa'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        actions: [
          if (_controller.hasDatabase && isCompact && status != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text('${_formatCount(status.nodeCount)} taxa'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (_controller.hasDatabase)
            if (isCompact)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: _controller.isSyncing ? 'Updating...' : 'Update DB',
                  onPressed: _controller.isSyncing
                      ? null
                      : () => _controller.syncFromNcbi(force: false),
                  icon: _controller.isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonalIcon(
                  onPressed: _controller.isSyncing
                      ? null
                      : () => _controller.syncFromNcbi(force: false),
                  icon: _controller.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 18),
                  label:
                      Text(_controller.isSyncing ? 'Updating...' : 'Update DB'),
                ),
              ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_controller.isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_controller.hasDatabase) {
      return _buildOnboardingView(theme);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Column(
            children: [
              if (_controller.isSyncing || _controller.syncError != null)
                _buildSyncBanner(theme),
              _buildSearchHeader(theme),
              if (_controller.query.trim().isNotEmpty)
                _buildSearchResultsBar(theme),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 400, child: _buildTreePane(theme)),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildInspectorPane(theme)),
                  ],
                ),
              ),
            ],
          );
        }

        final selected = _controller.selectedDetails?.node;
        return Column(
          children: [
            if (_controller.isSyncing || _controller.syncError != null)
              _buildSyncBanner(theme),
            Expanded(
              child: _mobileTabIndex == 0
                  ? Column(
                      children: [
                        Expanded(child: _buildTreePane(theme)),
                        if (selected != null)
                          Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                selected.scientificName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'TaxID: ${selected.taxId} • ${selected.rank}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Search Google',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.travel_explore,
                                      size: 20,
                                    ),
                                    onPressed: () => _searchGoogleName(
                                      selected.scientificName,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Ask Gemini',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.auto_awesome,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _askGeminiForTaxon(selected),
                                  ),
                                  const SizedBox(width: 4),
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        _openInspectorSheet(theme),
                                    icon: const Icon(
                                      Icons.info_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Inspect'),
                                  ),
                                ],
                              ),
                              onTap: () => _openInspectorSheet(theme),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildSearchHeader(theme),
                        const Divider(height: 1),
                        Expanded(
                          child: _controller.query.trim().isEmpty
                              ? const Center(
                                  child: Text(
                                    'Search scientific or common names',
                                  ),
                                )
                              : _buildSearchResultsList(
                                  theme,
                                  switchToTreeOnReveal: true,
                                ),
                        ),
                      ],
                    ),
            ),
            NavigationBar(
              selectedIndex: _mobileTabIndex,
              onDestinationSelected: (i) =>
                  setState(() => _mobileTabIndex = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.account_tree_outlined),
                  selectedIcon: Icon(Icons.account_tree),
                  label: 'Tree',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _openInspectorSheet(ThemeData theme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, _) => _buildInspectorPane(theme),
        );
      },
    );
  }

  Widget _buildOnboardingView(ThemeData theme) {
    final progress = _controller.syncProgress;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.biotech_rounded,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Download NCBI Taxonomy',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'No local taxonomy database was found. Download '
                  'new_taxdump.tar.gz directly from NCBI and build an '
                  'offline SQLite FTS5 index for instant fuzzy search and '
                  'tree browsing.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (_controller.isSyncing && progress != null) ...[
                  LinearProgressIndicator(value: progress.fraction),
                  const SizedBox(height: 10),
                  Text(progress.message, style: theme.textTheme.bodySmall),
                ] else ...[
                  if (_controller.syncError != null) ...[
                    Text(
                      _controller.syncError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _compactImport,
                    onChanged: (v) =>
                        setState(() => _compactImport = v ?? false),
                    title: const Text('Compact import (recommended for mobile)'),
                    subtitle: const Text(
                      'Skip non-specific leaf taxa (sp., uncultured, environmental samples) for smaller DB & faster indexing.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _controller.syncFromNcbi(
                      force: true,
                      compactImport: _compactImport,
                    ),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Download & Build Database'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncBanner(ThemeData theme) {
    final progress = _controller.syncProgress;
    final err = _controller.syncError;
    return Material(
      color: err != null
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    err ?? progress?.message ?? 'Updating...',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (err == null && progress != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: progress.fraction),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: _searchController,
              onChanged: _controller.setQuery,
              decoration: InputDecoration(
                hintText:
                    'Fuzzy search scientific or common name (e.g. Homo sapens)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _controller.setQuery('');
                        },
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          SegmentedButton<NameFilter>(
            segments: const [
              ButtonSegment(value: NameFilter.all, label: Text('All')),
              ButtonSegment(
                value: NameFilter.scientific,
                label: Text('Scientific'),
              ),
              ButtonSegment(value: NameFilter.common, label: Text('Common')),
            ],
            selected: {_controller.filter},
            onSelectionChanged: (sel) => _controller.setFilter(sel.first),
          ),
          FilterChip(
            label: const Text('Hide non-specific'),
            tooltip:
                'Hide Candidatus, sp., incertae sedis, unclassified, uncultured, environmental samples, and metagenomes',
            selected: _controller.hideNonSpecific,
            onSelected: _controller.setHideNonSpecific,
          ),
          FilterChip(
            label: const Text('Hide subspecies'),
            tooltip:
                'Hide everything below species level (subspecies, strains, etc.)',
            selected: _controller.hideSubspecies,
            onSelected: _controller.setHideSubspecies,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsBar(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_controller.isSearching)
              const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: _buildSearchResultsList(theme, shrinkWrap: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList(
    ThemeData theme, {
    bool shrinkWrap = false,
    bool switchToTreeOnReveal = false,
  }) {
    final results = _controller.searchResults;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          _controller.isSearching ? 'Searching...' : 'No matching taxa found.',
        ),
      );
    }

    void onSelect(int taxId) {
      if (switchToTreeOnReveal) {
        setState(() => _mobileTabIndex = 0);
      }
      _revealAndScroll(taxId);
    }

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final r = results[index];
        return ListTile(
          dense: true,
          title: Text(
            r.matchedName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              if (r.matchedName != r.scientificName) r.scientificName,
              'TaxID: ${r.taxId}',
              r.rank,
              r.nameClass,
            ].join(' • '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Search Google',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.travel_explore, size: 18),
                onPressed: () => _searchGoogleName(r.scientificName),
              ),
              IconButton(
                tooltip: 'Ask Gemini',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.auto_awesome, size: 18),
                onPressed: () => _askGeminiForTaxon(
                  TaxonNode(
                    taxId: r.taxId,
                    parentTaxId: 1,
                    rank: r.rank,
                    scientificName: r.scientificName,
                    childCount: 0,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => onSelect(r.taxId),
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: const Text('Reveal'),
              ),
            ],
          ),
          onTap: () => onSelect(r.taxId),
        );
      },
    );
  }

  Future<void> _searchGoogleName(String scientificName) async {
    final uri = buildGoogleSearchUri(scientificName);
    final ok = await openExternalUri(uri, launcher: widget.uriLauncher);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open browser for $uri')),
      );
    }
  }

  Future<void> _askGeminiForTaxon(TaxonNode taxon) async {
    final prompt = buildGeminiSummaryPrompt(taxon);
    Clipboard.setData(ClipboardData(text: prompt)).catchError((_) {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prompt copied to clipboard — paste it in Gemini.'),
        ),
      );
    }
    final uri = buildGeminiUri();
    final ok = await openExternalUri(uri, launcher: widget.uriLauncher);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open browser for $uri')),
      );
    }
  }

  void _revealAndScroll(int taxId) {
    _controller.revealTaxon(taxId);
    _treeFocusNode.requestFocus();
    _scrollTreeToTaxon(taxId);
  }

  void _scrollTreeToTaxon(int taxId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_treeScrollController.hasClients) return;
      final rows = _flattenVisibleTree(1, 0);
      final idx = rows.indexWhere((r) => r.$1.taxId == taxId);
      if (idx < 0) return;
      final pos = _treeScrollController.position;
      final target =
          (idx * _treeRowExtent - pos.viewportDimension / 2 + _treeRowExtent / 2)
              .clamp(0.0, pos.maxScrollExtent);
      _treeScrollController.jumpTo(target);
    });
  }

  void _ensureTreeIndexVisible(int index) {
    if (!_treeScrollController.hasClients) return;
    final pos = _treeScrollController.position;
    final top = index * _treeRowExtent;
    final bottom = top + _treeRowExtent;
    if (top < pos.pixels) {
      _treeScrollController.jumpTo(top.clamp(0.0, pos.maxScrollExtent));
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _treeScrollController.jumpTo(
        (bottom - pos.viewportDimension).clamp(0.0, pos.maxScrollExtent),
      );
    }
  }

  KeyEventResult _handleTreeKeyEvent(
    List<(TaxonNode, int)> rows,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (rows.isEmpty) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final selectedId = _controller.selectedTaxId;
    var currentIndex = rows.indexWhere((r) => r.$1.taxId == selectedId);
    if (currentIndex < 0) currentIndex = 0;

    if (key == LogicalKeyboardKey.arrowDown) {
      final nextIndex = (currentIndex + 1).clamp(0, rows.length - 1);
      _controller.selectTaxon(rows[nextIndex].$1.taxId);
      _ensureTreeIndexVisible(nextIndex);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final prevIndex = (currentIndex - 1).clamp(0, rows.length - 1);
      _controller.selectTaxon(rows[prevIndex].$1.taxId);
      _ensureTreeIndexVisible(prevIndex);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final node = rows[currentIndex].$1;
      if (_controller.canExpandNode(node)) {
        if (!_controller.expandedIds.contains(node.taxId)) {
          _controller.toggleExpanded(node.taxId);
        } else if (currentIndex + 1 < rows.length &&
            rows[currentIndex + 1].$1.parentTaxId == node.taxId) {
          _controller.selectTaxon(rows[currentIndex + 1].$1.taxId);
          _ensureTreeIndexVisible(currentIndex + 1);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final node = rows[currentIndex].$1;
      if (_controller.expandedIds.contains(node.taxId)) {
        _controller.toggleExpanded(node.taxId);
      } else if (node.parentTaxId != node.taxId) {
        final parentIndex =
            rows.indexWhere((r) => r.$1.taxId == node.parentTaxId);
        if (parentIndex >= 0) {
          _controller.selectTaxon(rows[parentIndex].$1.taxId);
          _ensureTreeIndexVisible(parentIndex);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown && _treeScrollController.hasClients) {
      final pos = _treeScrollController.position;
      final step = (pos.viewportDimension * 0.85);
      _treeScrollController.jumpTo(
        (pos.pixels + step).clamp(0.0, pos.maxScrollExtent),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp && _treeScrollController.hasClients) {
      final pos = _treeScrollController.position;
      final step = (pos.viewportDimension * 0.85);
      _treeScrollController.jumpTo(
        (pos.pixels - step).clamp(0.0, pos.maxScrollExtent),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildTreePane(ThemeData theme) {
    final rows = _flattenVisibleTree(1, 0);
    var maxDepth = 0;
    for (final r in rows) {
      if (r.$2 > maxDepth) maxDepth = r.$2;
    }

    return Focus(
      focusNode: _treeFocusNode,
      onKeyEvent: (_, event) => _handleTreeKeyEvent(rows, event),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'TAXONOMIC TREE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.max(
                  constraints.maxWidth,
                  280.0 + maxDepth * _treeIndent,
                );
                return Scrollbar(
                  controller: _treeScrollController,
                  thumbVisibility: true,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.vertical,
                  child: Scrollbar(
                    controller: _treeHorizontalScrollController,
                    notificationPredicate: (n) =>
                        n.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _treeHorizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        height: constraints.maxHeight,
                        child: ListView.builder(
                      controller: _treeScrollController,
                      itemExtent: _treeRowExtent,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final (taxon, depth) = rows[index];
                        final hasChildren = _controller.canExpandNode(taxon);
                        final isExpanded =
                            _controller.expandedIds.contains(taxon.taxId);
                        final isSelected =
                            taxon.taxId == _controller.selectedTaxId;

                        return InkWell(
                          canRequestFocus: false,
                          onTap: () {
                            _treeFocusNode.requestFocus();
                            _controller.selectTaxon(taxon.taxId);
                          },
                          child: Container(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer
                                    .withAlpha(110)
                                : null,
                            padding: EdgeInsets.only(
                              left: 6.0 + depth * _treeIndent,
                              right: 8,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: hasChildren
                                      ? InkResponse(
                                          canRequestFocus: false,
                                          radius: 12,
                                          onTap: () {
                                            _treeFocusNode.requestFocus();
                                            _controller
                                                .toggleExpanded(taxon.taxId);
                                          },
                                          child: Icon(
                                            isExpanded
                                                ? Icons.expand_more
                                                : Icons.chevron_right,
                                            size: 16,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    taxon.scientificName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      fontStyle: taxon.rank == 'species'
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ),
                                if (taxon.rank != 'no rank')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      taxon.rank,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<(TaxonNode, int)> _flattenVisibleTree(int taxId, int depth) {
    final node = _controller.nodeCache[taxId];
    if (node == null) return const [];
    final out = <(TaxonNode, int)>[(node, depth)];
    if (_controller.expandedIds.contains(taxId)) {
      final children = _controller.childrenCache[taxId] ?? const <TaxonNode>[];
      for (final child in children) {
        out.addAll(_flattenVisibleTree(child.taxId, depth + 1));
      }
    }
    return out;
  }

  KeyEventResult _handleInspectorKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_inspectorScrollController.hasClients) return KeyEventResult.ignored;

    final pos = _inspectorScrollController.position;
    final key = event.logicalKey;
    const lineStep = 48.0;
    final pageStep = pos.viewportDimension * 0.85;

    if (key == LogicalKeyboardKey.arrowDown) {
      _inspectorScrollController.jumpTo(
        (pos.pixels + lineStep).clamp(0.0, pos.maxScrollExtent),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _inspectorScrollController.jumpTo(
        (pos.pixels - lineStep).clamp(0.0, pos.maxScrollExtent),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _inspectorScrollController.jumpTo(
        (pos.pixels + pageStep).clamp(0.0, pos.maxScrollExtent),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _inspectorScrollController.jumpTo(
        (pos.pixels - pageStep).clamp(0.0, pos.maxScrollExtent),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInspectorPane(ThemeData theme) {
    final details = _controller.selectedDetails;
    if (details == null) {
      return const Center(child: Text('Select a taxon to inspect.'));
    }

    final selected = details.node;
    final lineage = details.lineage;
    final children = details.children;
    final hiddenChildCount = math.max(0, selected.childCount - children.length);

    final groupedNames = <String, List<String>>{};
    for (final n in details.names) {
      if (n.nameClass == 'scientific name') continue;
      groupedNames.putIfAbsent(n.nameClass, () => []).add(n.nameTxt);
    }

    return Focus(
      focusNode: _inspectorFocusNode,
      onKeyEvent: (_, event) => _handleInspectorKeyEvent(event),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _inspectorFocusNode.requestFocus(),
        child: SingleChildScrollView(
          controller: _inspectorScrollController,
          padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < lineage.length; i++) ...[
                if (i > 0) const Icon(Icons.chevron_right, size: 16),
                ActionChip(
                  label: Text(lineage[i].scientificName),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _revealAndScroll(lineage[i].taxId),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  selected.scientificName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontStyle: selected.rank == 'species'
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
              Chip(label: Text(selected.rank)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                hiddenChildCount > 0
                    ? 'NCBI TaxID: ${selected.taxId} • ${selected.childCount} direct child(ren) ($hiddenChildCount hidden)'
                    : 'NCBI TaxID: ${selected.taxId} • ${selected.childCount} direct child(ren)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${selected.taxId}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied TaxID ${selected.taxId}')),
                  );
                },
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Copy TaxID'),
              ),
              OutlinedButton.icon(
                onPressed: () => _searchGoogleName(selected.scientificName),
                icon: const Icon(Icons.travel_explore, size: 16),
                label: const Text('Search Google'),
              ),
              OutlinedButton.icon(
                onPressed: () => _askGeminiForTaxon(selected),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Ask Gemini'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final entry in groupedNames.entries) ...[
            Text(_titleCase(entry.key), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in entry.value) Chip(label: Text(name)),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (children.isNotEmpty) ...[
            Text(
              hiddenChildCount > 0
                  ? 'Direct Children (${children.length} of ${selected.childCount}, $hiddenChildCount hidden)'
                  : 'Direct Children (${selected.childCount})',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final child in children)
                    ListTile(
                      dense: true,
                      title: Text(child.scientificName),
                      subtitle: Text(
                        !_controller.canExpandNode(child) && child.childCount > 0
                            ? 'TaxID: ${child.taxId} • ${child.rank} • ${child.childCount} children (hidden)'
                            : 'TaxID: ${child.taxId} • ${child.rank} • ${child.childCount} children',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => _revealAndScroll(child.taxId),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
