# Finite intrinsic receiver/storage controls

Pinned BYOND 516.1687 compile-only controls; no runtime or profiler. Every source,
native image, raw compiler log and decoded procedure is hash-bound in receipt.json.

`vars`, `screen` and both movable/image `vis_contents` accept the list receiver
method `Copy()`. An untyped formal's `Copy()` is rejected as undefined; all four
nonexistent-method controls are also rejected. These certify the narrow list
receiver catalog entries, without allocating defaults or inferring modifier masks.

`/world.internet_address` and `/world.map_cpu` reads use exact Src-field getters.
Internet-address and image-vis-contents assignment controls use Src-field setters.
Map-cpu assignment and vars assignment are rejected as changing constant values;
the new catalog does not certify those bindings as mutable or invent flags.
World scalar declared types remain explicitly unsupported/opaque.

The inferred `field = new` controls additionally emit `(tag 40, payload 0)`, the
native list primitive encoding. Its payload is not an ordinary class-table index;
looking up class zero (the lexical owner in these images) was an incorrect
interpretation. Raw binaries and decoded words are unchanged. The constructor
observations agree with the narrow list receiver type facts above.
