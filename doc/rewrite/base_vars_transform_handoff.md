# Atom transform-history cohort (source only)

Owner directory: `code/core/atom/`. Current master baseline c3cb037784 has 539 rows (531 base vars, eight instance-list initializers). This cohort removes the five base vars declared by Transform.dm; the two required squish consumers in joke.dm and player_effects.dm read the same native sparse slots. No image transform fields, unrelated base vars, tracking declarations or gameplay effects are changed.

The five nullable components use existing `sparse(/atom, ..., type = num)` declarations. SetTransform's default arguments read each existing component, uniform scale still takes precedence, explicit null clears a component, numeric zero stays numeric, and matrix.Update executes the same scale/rotation/translation/others order. ClearTransform clears the five sparse slots and the built-in matrix. No new per-atom var or secondary shadow state is added.

Four new focused selectors under `dq_atom_transform_sparse` cover partial updates/independent atoms, null versus zero and reset, matrix composition without input mutation, and both actual squish consumers. They are wired through the existing guarded unit-test manifest. This source has not been generated, compiled, tested, baseline-updated or stamped. Root owns all verification and commits; no result is claimed.
