# Cupertino render evidence

[Open the screenshot gallery](screenshots/index.html). The [audit manifest](render-audit.json) records image hashes, fixture hashes, viewport dimensions and the exact manually reviewed images.

- 127 surfaces, exported by Swift as 254 closed/open fixtures.
- 338 render cases: 254 base cases, 36 appearance/font-scale variants, and 48 Material3 variants.
- 367 current PNGs, including 29 popup captures, all within a real 360 × 720 Skia test window.
- All fixture hashes match; no unknown-component or missing-scope diagnostics; closed fixtures have no popup roots.
- The current full desktop suite passed 401 tests, with one additional Android popup-properties unit test. The suite includes the focused search-field interaction that makes the Cancel surface visible before capture.

Manual review found and drove fixes for filled-button contrast, sheet bounds/content height, crowded dialog actions, and the test host's popup window size. Final reviewed images show readable controls and bounded sheet/dialog layouts in light/dark appearance, including font scale 1.4. The audit lists 22 representative images reviewed manually; the remaining cases are automated render coverage. After the hidden-sheet correction, the changed reviewed sheet captures were inspected again and all 367 image hashes were refreshed and verified against the current files.

Subsequent hardware checks exposed Android popup focus, stale text echoes, and hidden sheet content outside a bounded preview. Focused regressions now cover the Android properties implementation, rapid text/selection echoes, and a 720-point host around a 420-point sheet, including pixels outside the frame and an open/drag/close cycle. Those findings are not retroactively covered by the earlier screenshot review.

This evidence covers host JVM/Skia rendering. The catalogue lazy provider is a deliberate Kotlin test double; separate tests exercise the real Swift provider. All 879 vector/adaptive icons are tested. Android named painter/bitmap resource overloads depend on application assets; desktop has no named-asset resolver. [Android device acceptance](android-hardware/README.md) is recorded separately.
