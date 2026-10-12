# Static power content: Phase D handoff

Pure move commit `3265fa6ef3` relocates two native data-only files:

- `code/modules/power/lighting_neon.dm` to
  `code/domains/power/content/lighting_neon.dm`.
- `code/modules/power/tesla/generator.dm` to
  `code/domains/power/content/tesla/generator.dm`.

Both retain their exact original Git blob IDs (100% rename identity). The only
manifest edits replace their include paths at the same positions. No semantic
content changes were mixed into the move. Their last source changes were in
2025 and March 2026; no other lane edited either file that day.

Lane-ready passed on `b239c0183528`, merged with master `f208564b45`:
29 tests passed, zero failures; production compile zero errors; DreamChecker
zero diagnostics; analyzer and ratchets clean. Both mandatory pins, smoke tests
and incremental appearance checks ran. The requested `dq_p2_lights` parent is
abstract and did not run; no concrete lighting-case coverage is claimed.
The exact blob check proves the moved definitions retain their original data.
No full suite ran.

The separate snapshot commit carries only the cause-backed requirement pin
refresh for master's `f5007aa10f` menu fixes and existing serial stabilization;
the causes and affected classes are in `intended_changes.md`. Conversion pins
were not refreshed. No baseline was raised and no `ALLOW` was added.
