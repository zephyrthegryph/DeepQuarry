# A2 items initialization sweep

Before:194 rows (190 init_lines,4 world_reads). After analyzer update:98 init_lines,0 world_reads;96 removed. Global init baseline4115→4019;decl unchanged47.

Converted42 setup jobs and one keeps_if guard in36 production files; removed one dead commented-out bug-monitor initializer. Constant ashtray icon_state blank is now a type default.

Named setup jobs preserve original RNG/constructor interleaving; no reseeding, duplicate state, new fields, altered setter calls or altered relation/ownership declarations. Existing helper calls are used directly where possible. Complex post-parent jobs retain the complete job and its diagnostic messages. Same-type Zippo setup runs after the parent casing setup, preserving both the random draws and overlay removal.

New test include: code/modules/unit_tests/dq_a2_item_init.dm. Selectors dq_a2_item_init/* (10 tests), plus dq_look_pin and relevant existing dq_decl_starts/dq_hc_items coverage selected by root. No build/test/gen/baseline/commit run by this agent.

## Residuals by file
- `devices/communicator/cartridge.dm` (1 rows): Head commcard radio registration occurs before parent initialization; no equivalent early external-registration declaration is proven.
- `devices/communicator/communicator.dm` (4 rows): Observer address is built from the actual client/key, preference and real_name (genuine instance state).
- `devices/defib.dm` (1 rows): Tethered paddles are constructed before parent initialization; moving to phase-3 setup would change their availability/order.
- `devices/flipper.dm` (3 rows): Pre-parent emag and creation of the owned pAI; parent/D5 owns the new-owned-pAI site. Emotion must follow that complete chain.
- `devices/personal_shield_generator.dm` (8 rows): The selected weapon is constructed with its live owner then linked to that owner's actual cell; generator gun reads its live constructor owner. Changing ownership declarations is expressly excluded.
- `devices/pipe_painter.dm` (1 rows): Random mode is applied through its real setter; native rolls would preserve map overrides where the original always draws/overwrites.
- `devices/radio/intercom.dm` (4 rows): Two same-type Initialize definitions exist across intercom.dm and radio.dm; replacing both by setup would activate both jobs, potentially changing existing override behavior. Area-dependent power/subscription is also true map placement state.
- `devices/radio/radio.dm` (3 rows): Radio normalizes actual mapper frequency. The intercom broadcast cache has the duplicate same-type initializer issue above.
- `devices/radio/radiopack.dm` (1 rows): Tethered handset must exist before parent initialization.
- `devices/scanners/motion_tracker.dm` (4 rows): World observer subscription precedes parent init, followed by subscription of its actual constructor mob location; preserve phase and per-instance placement.
- `ghost_hunting/weapons.dm` (1 rows): Tethered proton gun is constructed before parent initialization.
- `paintkit.dm` (1 rows): Debug kit identity is configured before parent initialization through set_info; preserve its parent-read ordering.
- `stacks/stack.dm` (13 rows): Subtypes consume stacktype/in-hand sprite/amount/matter during their initializer. amount_at_make is a transient constructor param dropped before setup; preserve parent state normalization and sale setup order.
- `trash.dm` (2 rows): Persistence registration explicitly depends on mapload and persistence-ignore-mapload config; setup has no mapload argument or declaration preserving this filter.
- `weapons/extinguisher.dm` (3 rows): Random casing overlay is applied before parent initialization from actual mapper rand_overlays/item_state. Native rolls skips mapper overrides; preserve phase and draws.
- `weapons/id cards/cards.dm` (5 rows): Base reset_icon is read by multiple remaining ID subtype initializers outside this scope. Borg owner/name binds the actual robot constructor location.
- `weapons/material/material_armor.dm` (2 rows): Shared clothing parent resolves mapper/constructor material before subtype initialization. Moving it to setup changes material availability in the subtype chain.
- `weapons/material/material_weapons.dm` (13 rows): Shared material parent resolves material, builds scaled matter and conductivity before material subtype initializers use those values; keep the parent prerequisite and invalid-material outcome.
- `weapons/medigun/medigun_backpack.dm` (8 rows): Pre-parent tether construction is followed by live backlink and subtype-selected size/beam setup; retain the required ordering.
- `weapons/storage/internal.dm` (4 rows): Actual owner location is genuine instance state; parent explicitly reserves known guard-order repair and owner declarations from this sweep.
- `weapons/storage/storage.dm` (5 rows): Subtype initializers consume starting contents and calibration; moving parent lazy declaration/calibration after them changes contents visibility. Empty/map starts are genuine per-instance inputs.
- `weapons/tanks/tanks.dm` (3 rows): Tank parent applies blueprint, creates proxy and reads gas before multiple subtype initializers, including outside this folder. Keep the shared prerequisite order.
- `weapons/tools/transforming.dm` (3 rows): Conditional welder creation populates existing owned field before selecting initial tool mode. Migrating ownership declaration/starts is expressly excluded.
- `weapons/tools/weldingtool.dm` (5 rows): Mounted welders bind their actual containing weldpack/equipment from constructor placement; genuine per-instance references.

Exact residual fingerprints: remaining-fingerprints.txt. Expected deleted identities: expected-removed-fingerprints.txt.

## Static review
Read all initializer bodies in every baseline file before selecting conversions. Checked production subtype Initialize definitions tree-wide for converted holders: no remaining descendant initializer consumes the migrated job. Constructors still finish setup before materialization. Child objects/params exist before callbacks; keeps_if skips stand-in setup on rejection. Tests warm dview/status policies, scope coalesce, adopt only newly created paired detonators, and own MRE products explicitly. Stand-in test uses real public charge fields (no invented getters).

Only changed editor default is ashtray initial icon_state ashtray -> blank; initialized runtime was already blank and its material dish overlay/color/capacity job is retained. Existing raw per-instance assignments are moved verbatim, not renamed/aliased to dodge lints.
