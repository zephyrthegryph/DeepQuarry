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

Before the later compiler retirement, this landing also records real old-consent ordering and folder/closet admission boundaries. These tests run against unchanged consent and custom-slot production policies; no passing result is claimed until the combined focused gate completes.

Additional old-code boundaries capture real wield state, drake/horse shapes, saddlebag and Avida query effects, and twelve offline named-owner denials. They do not claim authenticated positive identity coverage. Production remains unchanged for these remaining semantic tables until their old-code gate is green.

Merge repair: current master replaced the ledger refresh API; resident-cost setters now call `ledger_refresh_contribution()` before publishing. Existing tests use real tracked setters, and marking-map keys remain associative keys rather than organ writes. A borrowed `pinned` relation preserves objects rather than deleting them. Transient hook plans finish with `spent()`, and receiver rebinding uses the existing leased context binder without acquiring a second query.

The setter conversion exposed thirteen changed initialization fingerprints. Complete tool/module configurations now run through ordered setup hooks. Malignant and stump identity setters run through preinit capabilities before organ placement; constructor tests cover forced tag/site, engineered growth, dead fallback and stump placement. Malignant's internal random-call order is unchanged, although moving it past ancestor setup may change the global RNG sequence. This does not authorize re-blessing unexplained snapshot changes.

The first combined gate failed compilation and ratchets and ran no runtime tests. Verification remains pending until the repair gate completes.
