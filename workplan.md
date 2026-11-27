# PhyloSurf — Project Workplan

**Last updated:** 2026-11-26  
**Current version:** `1.0.0+1`  
**Platforms:** Windows (desktop, packaged), Android (release APK built), macOS (configured, ready to build on macOS/CI)

---

## Completed Milestones

### Phase 1: Data Layer & Offline NCBI Sync
- [x] **NCBI Taxdump Ingestion** ([dmp_parser.dart](lib/data/dmp_parser.dart), [ncbi_sync_service.dart](lib/data/ncbi_sync_service.dart))
  - Downloads `new_taxdump.tar.gz` directly from NCBI FTP.
  - Streams and parses `nodes.dmp` and `names.dmp` in a background isolate with progress reporting.
  - Supports compact import mode and HTTP `ETag` / `Last-Modified` update checks.
  - Builds a staging SQLite database and swaps it atomically into place.
- [x] **Local SQLite Repository** ([taxonomy_database.dart](lib/data/taxonomy_database.dart), [models.dart](lib/data/models.dart))
  - Indexed storage for taxon nodes, names (scientific, common, synonyms, etc.), parent/child counts, and metadata.
  - Fast lineage traversal, child queries, and database status inspection.

### Phase 2: Search & Taxonomic Filtering
- [x] **Non-Blocking Fuzzy Search** ([search_worker.dart](lib/state/search_worker.dart), [fuzzy_scorer.dart](lib/data/fuzzy_scorer.dart))
  - Persistent background isolate for SQLite search so the UI never blocks.
  - Restricted Damerau-Levenshtein fuzzy scoring with word-level matching and name-class boosts (scientific, GenBank common, common, BLAST, synonym).
  - Supports filtering by name type (`All`, `Scientific`, `Common`) and TaxID lookup.
- [x] **Taxonomic Noise Filters** ([taxon_filter.dart](lib/data/taxon_filter.dart))
  - Toggle to hide non-specific / provisional taxa (`Candidatus`, `sp.`, `incertae sedis`, `unclassified`, `uncultured`, `environmental samples`, `metagenome`, `other sequences`).
  - Toggle to hide infraspecific ranks (`subspecies`, `strain`, `serotype`, `varietas`, `isolate`, `cultivar`, etc.).

### Phase 3: UI/UX & Research Integrations
- [x] **Interactive Taxonomy Explorer** ([main.dart](lib/main.dart), [taxonomy_controller.dart](lib/state/taxonomy_controller.dart))
  - Expandable hierarchical tree view with auto-scroll to selected taxa and keyboard navigation.
  - Taxon inspector showing rank, TaxID, all known names, clickable lineage breadcrumbs, and child taxa.
  - Browser-style Back / Forward navigation history.
  - Adaptive layout for desktop split-pane and compact/mobile tabbed views, with Material 3 light/dark system theming.
- [x] **External Research Links** ([external_links.dart](lib/utils/external_links.dart))
  - One-click Google Search for the selected taxon's scientific name.
  - Pre-formatted Gemini summary prompt handoff with taxon rank, scientific name, and NCBI TaxID.

### Phase 4: Branding, Testing & Windows Distribution
- [x] **App Branding**: Renamed app and executable to **PhyloSurf** with custom app icon (`assets/icon/phylosurf_icon.png`, `windows/runner/resources/app_icon.ico`).
- [x] **Automated Tests**: Backend/database/filter unit tests ([taxonomy_backend_test.dart](test/taxonomy_backend_test.dart)) and UI widget tests ([widget_test.dart](test/widget_test.dart)).
- [x] **Windows Release Build**: Verified `flutter build windows --release` producing `phylosurf.exe`.
- [x] **Windows Distribution Packages** ([phylosurf.iss](installer/phylosurf.iss), [package_windows.ps1](scripts/package_windows.ps1)):
  - Inno Setup `.exe` installer (`dist/PhyloSurf-1.0.0-Windows-x64-Setup.exe`) with per-user/all-users support, shortcuts, and uninstaller.
  - Self-contained portable `.zip` archive (`dist/PhyloSurf-1.0.0-Windows-x64-Portable.zip`).
  - Bundled MSVC runtime DLLs (`vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll`) for clean Windows 10/11 machines.
- [x] **Android Release Build**: Verified `flutter build apk --release` producing `phylosurf.apk`.
- [x] **macOS Platform Support** (`macos/`):
  - Scaffolded macOS Flutter runner (`flutter create --platforms=macos .`).
  - Enabled `com.apple.security.network.client` in `Release.entitlements` and `DebugProfile.entitlements` for NCBI downloads.
  - Configured `PhyloSurf` product name, bundle ID, and generated all macOS AppIcon PNG sizes (`16`–`1024`).

---

## Upcoming / Planned Work

### Phase 5: Release Polish & Documentation
- [x] **Update `README.md`**: Replaced Flutter template text with PhyloSurf overview, download targets, developer build commands, and release instructions.
- [x] **CI/CD Release Pipeline**: Added `.github/workflows/ci.yml` (analyze & test) and `.github/workflows/release.yml` (automated Windows, macOS, and Android release builds + SHA256 checksums on `v*` tags).
- [ ] **Add `LICENSE` & Push to GitHub**: Choose a license, create the GitHub repository, push `main`, and tag `v1.0.0`.
- [ ] **Clean Up Remaining Template Metadata**: Update `pubspec.yaml` package name/description (`ncbi_taxonomy_explorer` -> `phylosurf`) and `CompanyName` / `LegalCopyright` in `windows/runner/Runner.rc`.
- [ ] **Code Signing (Optional)**: Sign Windows installer/exe, macOS `.app` (notarization), and Android APK with a dedicated release keystore.

### Phase 6: Additional Platforms & Feature Enhancements
- [ ] **Android Release Packaging**: Build and test signed release `.apk` / `.aab` on physical Android devices.
- [ ] **Additional Desktop Targets (Optional)**: Evaluate macOS and Linux desktop builds.
- [ ] **User Quality-of-Life Features**:
  - Bookmarks / pinned taxa persisted locally.
  - Export selected subtree or lineage (CSV / JSON / Newick).
  - Direct links to NCBI Taxonomy Browser / Wikipedia / GBIF in the inspector.
