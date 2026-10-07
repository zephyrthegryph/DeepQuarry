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

The inferred `field = new` controls are preserved as separate observations, not
declared-type authority: screen/vis-contents compile to tag-40 class index zero,
the lexical owner, rather than a list class. Constructor inference is a separate
contract and must not be inferred from the list receiver proof.
