# Standalone damage threshold runtime contract

This reproduces the historical `dq_damage_band_at` threshold loop with three
typed rule objects, then independently computes its result using `max`.
Seven ratios from `dq_damage_flavour_bands` and all three exact threshold
boundaries pass through integrity multiplication by 200 and division by 200.
Each backend must match explicit expected bands, not merely agree with the
other backend. Any runtime error rejects the fixture.

It does not reproduce the game's tracked integrity, rule queue, flush, settle,
inheritance, timing or accumulated state. A pass cannot explain or close the
historical full-suite damage-flavour divergence.

Run `run.py` with the same authenticated `--native`, `--template`, `--dm`,
`--dd` and corresponding `--*-sha256` arguments documented in
`../power_retirement_runtime/README.md`, plus an owned E: `--output-root`.
The imported launcher preserves version/SHA pins, separate source copies,
native pair acquisition, owned watchdog cleanup and its sampled 4GB budget.
No fixture execution has been claimed by adding these sources.
