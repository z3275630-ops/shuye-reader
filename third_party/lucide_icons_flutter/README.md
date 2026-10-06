# Lucide default-weight subset for Shuye

Derived from the published `lucide_icons_flutter 3.1.22`, retaining the original default glyphs, codepoints, family, package name and `IconData` declarations. This is a local modified subset, not an unmodified upstream release. The Flutter adapter uses the current SDK's final `IconData` API.

Only names used by `lib/app_icons.dart` and their default font glyphs are included. Six unused weight families, inline SVG documentation and unrelated symbols are omitted. No shared SDK or pub cache files are changed. The root package pins this directory via a path dependency; source hashes and published archive digest are in `audit.json`.

Package code uses the upstream MIT `LICENSE`; Lucide ISC / Feather MIT notices are additionally retained in the app's `assets/licenses/Lucide.txt` and shown in the license page.

To add an icon, update the adapter, then regenerate from the unmodified audited upstream package with FontTools 4.66.1:

```sh
python tools/subset_lucide.py /path/to/lucide_icons_flutter-3.1.22
dart format third_party/lucide_icons_flutter/lib
```

The tool verifies the source hashes before changing this subset. Review the generated declarations, font coverage, license and release APK cost together. Icons are static font glyphs; there is no SVG parser or network fetch at runtime.
