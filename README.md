# PhyloSurf

An offline-first **NCBI Taxonomy** explorer built with Flutter for Windows, macOS, and Android.

## Key Features
- **Offline-First Full NCBI Taxonomy Database**: Downloads and indexes `new_taxdump.tar.gz` locally into SQLite with one-click update checks (`ETag` / `Last-Modified`) and atomic database swaps.
- **Fast, Non-Blocking Fuzzy Search**: Searches scientific names, common names, synonyms, and NCBI TaxIDs in a background isolate with fuzzy ranking.
- **Interactive Tree & Lineage Navigation**: Expandable phylogenetic tree, detailed taxon inspector, clickable lineage breadcrumbs, and browser-style Back/Forward history.
- **Neural Scientific-Name Pronunciation (TTS)**: One-click Anglicized text-to-speech on every taxon page powered by offline **KittenTTS Nano** (`sherpa_onnx`, 24 kHz neural voice downloaded once on first use, ~25 MB) with a custom Latin/Greek IPA phonemizer and automatic OS-native `flutter_tts` fallback.
- **Smart Taxonomic Noise Filtering**: Toggle filters to hide provisional/non-specific entries (`sp.`, `Candidatus`, `unclassified`, `uncultured`, `metagenome`, `incertae sedis`) and infraspecific ranks (subspecies, strains, isolates, etc.).
- **Research Integrations**: One-click **NCBI Taxonomy**, **Google Search**, and pre-formatted **Gemini** summary prompt handoff for any selected taxon or search result.

## What's New in v1.1.0
- **Neural Scientific-Name Pronunciation**: Added a speaker button next to each taxon's scientific name powered by offline **KittenTTS Nano** (`kitten-nano-en-v0_2-fp16`, downloaded once on demand) with an Anglicized Latin/Greek IPA phonemizer, background synthesis isolate, in-memory WAV cache, and automatic `flutter_tts` fallback.
- **Direct NCBI Taxonomy Links**: Added one-click links to the official NCBI Datasets Taxonomy page (`datasets/taxonomy/<taxId>`) alongside Google Search and Gemini on every taxon page, search result, and mobile quick bar.

## Downloads
Prebuilt release binaries are published on the **GitHub Releases** page:
- **Windows (x64)**: `PhyloSurf-<version>-Windows-x64-Setup.exe` (installer) or `PhyloSurf-<version>-Windows-x64-Portable.zip` (portable)
- **macOS**: `PhyloSurf-<version>-macOS.zip`
- **Android**: `PhyloSurf-<version>-Android.apk`

## Development

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`stable` channel, Dart `^3.14.0`)
- Platform toolchain:
  - **Windows**: Visual Studio with Desktop development with C++, [NuGet CLI](https://learn.microsoft.com/en-us/nuget/install-nuget-client-tools) (`winget install Microsoft.NuGet`), plus [Inno Setup 6](https://jrsoftware.org/isinfo.php) for packaging the `.exe` installer
  - **macOS**: Xcode + CocoaPods
  - **Android**: Android SDK (API 34+) + JDK 17

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

## License
This project is licensed under the [MIT License](LICENSE).
