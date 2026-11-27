# PhyloSurf

An offline-first **NCBI Taxonomy** explorer built with Flutter for Windows, macOS, and Android.

## Key Features
- **Offline-First Full NCBI Taxonomy Database**: Downloads and indexes `new_taxdump.tar.gz` locally into SQLite with one-click update checks (`ETag` / `Last-Modified`) and atomic database swaps.
- **Fast, Non-Blocking Fuzzy Search**: Searches scientific names, common names, synonyms, and NCBI TaxIDs in a background isolate with fuzzy ranking.
- **Interactive Tree & Lineage Navigation**: Expandable phylogenetic tree, detailed taxon inspector, clickable lineage breadcrumbs, and browser-style Back/Forward history.
- **Smart Taxonomic Noise Filtering**: Toggle filters to hide provisional/non-specific entries (`sp.`, `Candidatus`, `unclassified`, `uncultured`, `metagenome`, `incertae sedis`) and infraspecific ranks (subspecies, strains, isolates, etc.).
- **Research Integrations**: One-click Google Search and pre-formatted Gemini summary prompt handoff for any selected taxon.

## Downloads
Prebuilt release binaries are published on the **GitHub Releases** page:
- **Windows (x64)**: `PhyloSurf-<version>-Windows-x64-Setup.exe` (installer) or `PhyloSurf-<version>-Windows-x64-Portable.zip` (portable)
- **macOS**: `PhyloSurf-<version>-macOS.zip`
- **Android**: `phylosurf.apk`

## Development

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`stable` channel, Dart `^3.14.0`)
- Platform toolchain:
  - **Windows**: Visual Studio with Desktop development with C++, plus [Inno Setup 6](https://jrsoftware.org/isinfo.php) for packaging the `.exe` installer
  - **macOS**: Xcode + CocoaPods
  - **Android**: Android SDK + JDK 17

### Run Locally
```bash
flutter pub get
flutter test
flutter run
```

### Build Release Packages
- **Windows (installer + portable ZIP)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\package_windows.ps1 -Rebuild
  ```
- **Android APK**:
  ```bash
  flutter build apk --release
  ```
- **macOS App** *(requires macOS)*:
  ```bash
  flutter build macos --release
  ```

## Releasing via GitHub Actions
1. Bump `version:` in `pubspec.yaml` and commit to `main`.
2. Tag and push:
   ```bash
   git tag v1.0.0
   git push origin main --tags
   ```
3. The `.github/workflows/release.yml` workflow automatically builds Windows, macOS, and Android release artifacts and publishes them to GitHub Releases.
