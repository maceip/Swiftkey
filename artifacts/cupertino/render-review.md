# Cupertino render evidence

[Open the screenshot gallery](screenshots/index.html). The [audit manifest](render-audit.json) records image hashes, fixture hashes, viewport dimensions and the exact manually reviewed images.

- 127 surfaces, exported by Swift as 254 closed/open fixtures.
- 338 render cases: 254 base cases, 36 appearance/font-scale variants, and 48 Material3 variants.
- 367 current PNGs, including 29 popup captures, all within a real 360 × 720 Skia test window.
- All fixture hashes match; no unknown-component or missing-scope diagnostics; closed fixtures have no popup roots.
- The full native suite passed 389 tests. A subsequent focused two-case run additionally focused the search field and verified the Cancel surface before capture.

Manual review found and drove fixes for filled-button contrast, sheet bounds/content height, crowded dialog actions, and the test host's popup window size. Final reviewed images show readable controls and bounded sheet/dialog layouts in light/dark appearance, including font scale 1.4. The audit lists the 21 representative images reviewed manually; the remaining cases are automated render coverage.

This evidence covers host JVM/Skia rendering. The catalogue lazy provider is a deliberate Kotlin test double; separate tests exercise the real Swift provider. All 879 vector/adaptive icons are tested. Android named painter/bitmap resource overloads depend on application assets; desktop has no named-asset resolver. Android device acceptance is recorded separately.
