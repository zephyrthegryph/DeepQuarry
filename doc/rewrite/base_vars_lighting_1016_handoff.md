# Lighting base-state source cohort

Original lighting baseline: 10 declarations. Source conversion: six removed;
four runtime-reference declarations remain. No generation, baseline update,
DreamChecker, build or tests were run by this source author.

Five configuration fields now live in the inheriting lighting_config type trait:
light_system, light_flags, light_cone_x_offset, light_cone_y_offset and
blocks_emissive. Content defaults became configure(lighting_config(...)) in each
type's existing CAPABILITIES block; the global duplicate-block audit relocated
four entries into their already-existing blocks. Read sites use lighting_of().
Map/VV old names are registered in var_names, not discarded. Runtime overrides
use the existing copy-on-write set_trait publisher. The actual set_light_flags
API retains its old-value return and notice, including VV's native trait name.
Null-safe helmet reads retain null semantics instead of reading a default trait.

The transient affecting_dynamic_lumi contribution is a numeric sparse slot.
Its calculation still subtracts the previous contribution and adds only the
maximum live source, preserving intrinsic luminosity. It clears at zero.

Tests in dq_base_vars_lighting_tests.dm (pending root DME wiring/verification):
- /datum/unit_test/dq_base_vars_lighting: inherited flashlight defaults, shared
  immutable type profile, per-holder copy-on-write old map-name override, real
  light flag attachment and admin detach observer behavior.
- /datum/unit_test/dq_base_vars_lighting/luminosity: independent source maxima,
  removal of the strongest source, intrinsic restoration and sparse cleanup.

## Four remaining owned-reference fields

light, light_sources, em_block and overlay_light retain their declarations.
They must not be converted into unowned sparse references. A naive lazy record
held by a sparse link with OTHER_DELETE_ME changes disposal from the original
atom's phase-3 owned-field pass into a phase-2 relation cascade, and runs the
ownership_field_disposed hook on the record rather than the original atom.
The existing dq_destroy_transaction_runtime_ledger_order regression explicitly
observes that original light hook while its containment ledger still exists.

owns_one currently reads holder.vars and has no sparse-owned endpoint form;
containment slots accept movable occupants, not the static light datum. A
phase-aware sparse-owned slot or record ownership contract is required to
preserve that disposal contract without inventing raw reference shadow storage
or manually forwarding lifecycle hooks. No such workaround is included here.

## Shared-file coordination

The behaviour author's sparse swarm link in lighting_atom.dm is preserved.
Overlapping lighting-only hunks include config reads in atoms_movable.dm,
lighting defaults in simple_mob.dm and one configure entry in the existing
carbon CAPABILITIES block in library/providers/hands.dm. All other edits by
behaviour, heat and vore authors are retained. Root owns staging and commits.
