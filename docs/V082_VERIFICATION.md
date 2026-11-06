# Linqo v0.8.2 verification — 6 November 2026

Linqo remains in active development. This report covers the Android ARM64 development preview, version **0.8.2+14**, prepared for the [v0.8.2 release](https://github.com/NotAl2/Linqo/releases/tag/v0.8.2).

## Changes

- Finite native welcome animations demonstrate sharing into Linqo and turning a caption into an organized recipe. They support reduced motion, background/inactive pausing and replay; no video or model runs during the demonstration.
- Whole-source classification provides structural guardrails before model-sized parts. Publisher controls and author biographies are filtered; supported inline recipe captions become original source spans. Saved source text remains intact.
- Recipes show ingredients, numbered steps and stated serving size. Articles show concise highlights, tutorials show ordered instructions, and places have their own layout. Repetitive evidence dropdowns and the raw-input section are replaced by **View saved source** in the save menu.
- Ink splashes, whole-screen selection fading and the overlapping Favourites checkmark were removed. Resolved preview file handles are bounded and retained across filter changes.
- The compact optional model and two-thread default are unchanged. Donations remain optional; there are no paid limits or licensing accounts.

## Validation

- A full host regression run passed **139 tests**. After the final UI corrections, **19 targeted UI tests** passed. These runs overlap and must not be added together as a unique test count.
- Final static analysis: **No issues found**. `git diff --check` passed.
- Physical Redmi Note 7 Pro, Android 12: recipe, general article, setup tutorial and place classifications passed with the existing local model and **two threads**. The recipe retained three ingredients, three preparation steps and **Serves 2**. Preferred-source controls were not retained as extracted facts.

| Short synthetic fixture | Extraction time |
|---|---:|
| Tomato pasta recipe | 17.231 s |
| Local AI article | 14.948 s |
| Backup setup guide | 16.141 s |
| National Gallery place | 16.596 s |

These are short-fixture observations on one device, not benchmarks for all content or guarantees of frame rate, battery use or thermal behavior. Classification, public content fetching and model selection of useful spans remain best effort. Missing facts are not estimated.

Native captures of the recipe/article reading views and complete tutorial pages were inspected. The final chip-only correction then passed targeted UI tests and was installed in the normal app; the extraction runtime was unchanged by that correction. scrcpy-mcp 0.5.0 with scrcpy 3.3.4 was configured locally and its live capture and MCP input paths verified; it is development tooling, not an app dependency.

## Data preservation and packaging

The normal APK was installed with `adb install -r`; no uninstall, clear-data, model deletion or model download occurred. Android's app-data identity remained unchanged. Four explicitly authorized **[Test]** samples were added only to the owner's test device, not shipped as automatic seed data. Repeating the harness reused those four IDs and preserved the library, collections, preferences and model-selection fingerprints. The initial sample insertion advanced the ordinary support save counter; no payment or account state exists. The original USB stay-awake setting was restored.

The final APK is **72,566,264 bytes** (72.6 MB decimal). Its SHA-256 is:

```text
7b1b181d78f6251aa8a5cbdaf8f1b7dc2252c59df6deb4733980a5c2f0c79492
```

The APK contains no GGUF model or tutorial videos. The release includes `SHA256SUMS.txt` and a dependency/native-runtime license bundle regenerated from the final APK. Existing development signing is retained for compatible updates; this is not a production/Play Store signing release.
