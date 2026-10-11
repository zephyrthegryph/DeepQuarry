# Native acceptance consumers

This branch converts 150 legacy declaration tables across 43 content files, using
native requirements and the shared acceptance context. These are 122 replacements,
24 explicitly empty declarations and four appended declarations. The declaration
inventory falls from 323 to 173; the remaining tables are a separate landing.

The old-code coverage was recorded before these conversions on the acceptance
foundation branch: 140 new type recordings, with no changed rows in existing pins.
Inherited-row factoring is recorded separately and is not counted as coverage.

Equipment queries carry the wearer, mover, destination, slot and channel. The
default equipment catalog supplies native ordered requirements. Instance refits
and adopted constraints use immutable plans and the existing tracked override map;
explicitly empty declarations remain distinguishable from absent declarations.

Declared slots accept compiled native requirements. Storage insertion and removal
use pure admission requirements, while the real transfer still performs removal
and insertion effects. Capacity previews account for live resident costs without
changing custody or cached accounting. Mutable providers publish their actual
dependencies; unsupported property providers do not advertise empty read sets.

Focused regression coverage includes declared-slot custody, distinct wearer and
mover behavior, refit/adoption snapshots, ordered transfer refusals, real removal
effects, source topology and finite versus unbounded capacity. Verification and
the lane-ready stamp are pending; no passing result is claimed yet.

The legacy compiler and the remaining 173 tables are retained only for their
unconverted consumers. Their final removal belongs to the following landings.

Static review caught and repaired mixed-protocol suit-storage observations and
missing closet resident-cost dependencies. Transfer callback guards collect their
real cross-entity and relation-hop dependencies, including while a guard is false.
No snapshot changes have been blessed for these repairs.

Literal dotted-path action guards have no current evaluator contract and no
production insertion/removal needs use them. They remain a framework gap rather
than receiving a fabricated metadata provider. Display-name-only direct renames
also require their actual publication contract; administrative edits already
invalidate through the existing edit dispatcher.
