# Machine thermal configuration and active output

Source-only; three `base_var` rows removed, verification pending. Declared heat
output and dissipation are genuine native type-trait data (`machine_heat()`),
shared by type. Only telecomms and RD servers had production defaults; their
existing capability blocks now configure the same wattage/conductance. All actual
readers use the typed trait reader. The engine's existing per-instance trait
writer, published key, inheritance, explicit null and legacy VV/map-name routing
are retained. No per-machine duplicate config record is allocated.

The current power fed into a native heat body is optional runtime state, stored
in a declared numeric sparse slot while nonzero. `set_heat_output()` retains all
original heat-body creation, keep/power calls, zeroing and early-return order.
Heat watches, native body handles and fire-turf relationships are untouched.

Focused selectors: `dq_h4_machine_heat_regulator` (existing real powered, unpowered,
broken and halted server behavior) and `dq_h4_machine_heat_trait_home` (type
inheritance, TRAIT_NONE, shared identity, copy-on-write isolation, old name routing,
and absence of idle output storage). The existing fixture's old config defaults
move into its single capability block without changing values.
