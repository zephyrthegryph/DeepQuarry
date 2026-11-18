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
window that has no export, horizontal page overflow, elements running off the right edge (`off-right:N(innermost offenders)`; a LabeledList's designed 1em overhang is not counted), a titled section with nothing in it and no word saying so (`empty-section:N(titles)`, use `EmptyState`), and content a section scrolls sideways (`h-scroll`, the narrow fallback of `styles/dq/narrow.scss`; reported, not a failure).
Exit status is 1 on exceptions, blank renders, missing exports or overflow.

## Window fit

Every window fits its height to its content at run time (`tgui/packages/tgui/layouts/fitWindow.ts` `measureFitHeight`, used by
`layouts/Window.tsx`): after it opens and whenever its content changes, it measures the content with every scroll box and fill
layout released to what it holds, and resizes to that, at least 120 px and at most 90% of the screen (a longer list scrolls).
It stops for good once the player resizes the window (a saved geometry carries `sized`), and a window whose content fills
whatever it gets (a camera or map view, `ByondUi`) passes `autoFit={false}`. Docked in the right-hand column, an entry the
player has not sized takes its content's height the same way (`tgui-panel/column/Column.tsx`, the model's `fit` action), up to
the room the chat leaves.

The render check reports `slack:Npx` (space under the content) and `overfull:Npx` (content cut off or scrolling while the
window could still grow) over 16 px, at the window's own width and docked (`--widths std,dock`: `?dock=1` renders the window
in the real column above a stand-in for the chat).

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

## Reviewing many windows

```sh
bun tools/tgui_preview/montage.ts E:/dq-cache/tgui-preview/runs/latest --per 12 --scale 0.5    # grids of 12 shots, NN.png + NN.txt
bun tools/tgui_preview/compare.ts <beforeRun> <afterRun>                                       # before/after sheet of what changed
```

`montage.ts` packs a run's shots into labelled grids (an agent can read one image instead of a dozen); `--only-problems`,
`--narrow`. `compare.ts` pairs the shots that differ between two runs, most changed first, plus the shots only the newer run
has, into `<afterRun>/compare/index.html` with the PNGs copied beside it. To shoot an older version of the windows, build a bundle
from it into another folder and pass `--bundle <dir> --reuse`.

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
window, numeric `ref`/`*_ref` ids renumbered, the dummy's name replaced, clock and timer readings zeroed), so a recapture diffs only
where the data changed. Measured over two captures of the same tree (2026-11-18): 320 of 326 fixtures identical. Of the six,
three (a map control id, a chat session stamp, a minutes clock) are normalised since; the profiler windows (OmProfiler,
SchedulerProfiler, ControllerOverview) still change, since their numbers are the measurement itself. Commit the result.

## Sprites

The census also generates every spritesheet (legacy and iconforge batched). capture.ts copies the CSS and PNGs into
`E:/dq-cache/tgui-sprites/current` (its own cache table, so evicting render runs never takes it) with their URLs pointed at the copies and writes `sprites/index.json`; the preview page loads
every sheet's CSS and maps `resolveAsset()` names to the copies, so `classes(['vending32x32', ...])` and asset images show the real
sprites. `DmIcon` needs no capture: the preview's `Byond.iconRefMap` maps every `.dmi` path to `dmi/<path>`, and the render server
crops that state/dir/frame out of `icons/gen/<path>` (`tools/tgui_preview/png.ts`). States it cannot find are listed in
`report.json` (`missingSprites`).

## Files

- `tgui/packages/tgui/preview/` the page (`index.tsx`), the BYOND stand-in (`byond.ts`), the alignment checks.
- `tools/tgui_preview/render.ts` the renderer (CDP over one WebSocket, no npm packages), `capture.ts`, `png.ts`, `montage.ts`, `compare.ts`.
- `tools/tgui_preview/check.ts` the older alignment sweep, `shoot.ts` and `sheet.ts` the older one-process-per-shot shooter.
- Cache: `E:/dq-cache/tgui-preview` (`[cache.tgui-preview]` in `tools/ci/disk_budget.toml`).
