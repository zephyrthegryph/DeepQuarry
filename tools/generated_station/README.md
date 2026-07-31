# Generated-station visual reference

`southern_cross_reference.json` is the checked-in acceptance corpus for room scale and
fixture richness. `measure_southern_cross.py` rebuilds it directly from all three live
Southern Cross station decks. A room sample is a connected non-wall floor component
sharing one exact mapped area. Functional occupancy deliberately excludes utilities,
lights, alarms, doors, windows, pipes, and decals, so infrastructure cannot make an
otherwise empty room pass.

The role profiles retain mapped p25/median occupancy, p75 largest-empty-region ratio,
fixture count, and normalized fixture-family diversity. Rust uses the p25 values as
comparison gates and furnishes toward the mapped median. This makes the comparison
falsifiable: the source maps can be remeasured after a mapping change, rather than
silently tuning constants against generated output.

The reference is intentionally statistical. Generated rooms should share the live
station's scale and recognizable activity clusters without copying its exact rectangles.
The randomized Rust suite owns macro geometry. The DM physical regression owns spawned
fixtures, utilities, atmosphere, lighting, access, and degradation reporting.
