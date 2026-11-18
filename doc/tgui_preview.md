# Rendering tgui windows (preview, fixtures, sprites, regression)

Every tgui window can be rendered in headless Chrome from fixture data, with real game sprites, in one command. Use it to look at
a window while you change it, to sweep every window for crashes, blank or clipped layouts, and to diff against a baseline.

## One command

```sh
bun tools/tgui_preview/render.ts Vending                  # one window (and its presets), standard + narrow width
bun tools/tgui_preview/render.ts Ntos --reuse             # every window whose name contains "Ntos", reusing the last bundle
bun tools/tgui_preview/render.ts                          # every fixture (~600 shots, about a minute)
```

Output: `E:/dq-cache/tgui-preview/runs/latest/` (`--label x` writes `runs/x`, `--out` anywhere): one PNG per shot
(`<Window>[.<variant>][@narrow].png`), `report.json`, and `index.html`, the contact sheet (problems first, a filter box, a
"problems only" toggle). Open the PNGs directly (an agent can Read them) or the sheet in a browser.

Options: `--jobs N` parallel pages (default 6, one browser), `--widths std,narrow` (narrow is 360 px), `--theme <name>` draws
every window in one theme (`console` is the default dark look; `ntos`, `paper`, `retro`, ...), `--reuse` skips the bundle
rebuild (about 40 s; rebuild after editing TSX/SCSS).

Each shot is checked for: a JS exception or console error, a blank render (one colour over 99% of the shot, or no text), a
window that has no export, horizontal page overflow, and elements running off the right edge (`off-right:N(first classes)`).
Exit status is 1 on exceptions, blank renders, missing exports or overflow.

## Regression mode

```sh
bun tools/tgui_preview/render.ts --save-baseline E:/dq-cache/tgui-preview/baseline      # once, on master
bun tools/tgui_preview/render.ts --reuse --baseline E:/dq-cache/tgui-preview/baseline  # after a change
```

A shot whose share of differing pixels (any channel off by more than 16/255) exceeds `--threshold` (default 0.005, 0.5%) is
`REGRESSED:<pct>`. To make shots repeatable the page seeds `Math.random`, runs CSS animations to their end at once, turns transitions off, and in regression mode
takes a second frame 0.5 s later and ignores pixels that moved between the two (GIFs, clocks). Measured over two runs of all 733
shots of the same tree (2026-11-18): 728 differ by 0 pixels; the largest remaining difference is 0.38% (RecyclerInterface, whose
GIF frame period is longer than the 0.5 s gap), so the default sits above that.

## Fixtures

The preview picks a window's data, first found:

1. `tgui/packages/tgui/interfaces/__fixtures__/windows/<Window>.json`: hand-written, every ui_shape key set (renderAll.test checks it).
2. `__fixtures__/captured/<Window>.json`: real data captured from the game by the census (below).
3. `__fixtures__/ui_data.json`: the unit-test capture (`/datum/unit_test/dq_tgui_ui_data_fixtures`).

**Presets** (variants per window) are `__fixtures__/windows/<Window>.<variant>.json` (`Vending.empty.json`, `ChemMaster.full.json`,
`Fax.error.json`): only the keys that differ, laid over the base data. The renderer shoots each as `<Window>.<variant>.png`;
renderAll.test renders each too. In a browser: `index.html?w=<Window>&v=<variant>` (`v=captured` forces the capture).

**Capture real data** for every window:

```sh
bun tools/tgui_preview/capture.ts           # runs the ui_census bench, then writes the fixtures and the sprite cache
bun tools/tgui_preview/capture.ts --skip-bench
```

The ui_census bench (`code/tests/benchmarks/ui_census.dm`) builds every declared window for a dummy viewer and writes
`data/tgui_fixtures/census.json`; capture.ts writes one fixture per window with volatile values made stable (refs renumbered per
window, the dummy's name replaced, clock readings zeroed), so a recapture diffs only where the data changed. Commit the result.

## Sprites

The census also generates every spritesheet (legacy and iconforge batched). capture.ts copies the CSS and PNGs into
`E:/dq-cache/tgui-preview/sprites` with their URLs pointed at the copies and writes `sprites/index.json`; the preview page loads
every sheet's CSS and maps `resolveAsset()` names to the copies, so `classes(['vending32x32', ...])` and asset images show the real
sprites. `DmIcon` needs no capture: the preview's `Byond.iconRefMap` maps every `.dmi` path to `dmi/<path>`, and the render server
crops that state/dir/frame out of `icons/gen/<path>` (`tools/tgui_preview/png.ts`). States it cannot find are listed in
`report.json` (`missingSprites`).

## Files

- `tgui/packages/tgui/preview/` the page (`index.tsx`), the BYOND stand-in (`byond.ts`), the alignment checks.
- `tools/tgui_preview/render.ts` the renderer (CDP over one WebSocket, no npm packages), `capture.ts`, `png.ts`.
- `tools/tgui_preview/check.ts` the older alignment sweep, `shoot.ts` and `sheet.ts` the older one-process-per-shot shooter.
- Cache: `E:/dq-cache/tgui-preview` (`[cache.tgui-preview]` in `tools/ci/disk_budget.toml`).
