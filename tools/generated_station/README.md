# Generated-station visual reference

`southern_cross_reference.json` is the checked-in acceptance corpus for room scale and
fixture richness. It was measured from the live Southern Cross map rather than chosen
from generator output. Rust uses the same three size bands through the catalog's
`content_area` and `ideal_usable_tiles` fields; DM validates the usable-area contract
before furnishing.

The reference is intentionally statistical. Generated rooms should share the live
station's scale and recognizable activity clusters without copying its exact rectangles.
The randomized Rust suite owns macro geometry. The DM physical regression owns spawned
fixtures, utilities, atmosphere, lighting, access, and degradation reporting.
