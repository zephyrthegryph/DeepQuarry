# Return/constructor provenance cohort

Pinned checker: 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0).
These are independent observations, not a completeness certificate. No reference
diagnostic is filtered. Header defaults are intentionally not evaluated by the
reference. Static/inferred new visits genuine New arguments; list-without-New
and dynamic NewMiniExpr intentionally skip their arguments. locate evaluates
its arguments before its in-list. New/locate type assumptions DO NOT establish
a static field receiver; those warning/fix-hint contexts remain Unsupported.
