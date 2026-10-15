# A4 machinery init audit

Base: origin/master 274d176a88. Branch codex/A4. Worktree E:/projects/dq-wt/codex-A4.

Before baseline: init_lines 354, world_reads 10. Source/identity audit predicts init_lines approximately 159, world_reads 0; only the root analyzer update can certify final counts. No baseline has been edited here.

46 production files changed. Replaced completed-initialization jobs with named setup hooks (world radio/listener registration, declared-child configuration, research/library loading, department registration, type-choice table compilation, unique names, visual geometry/overlays). Split unrelated teleporter wiring/linking and screen-overlay/radio jobs. Existing TRACKED lines, setter-call text and ownership/reference declarations are untouched. Frames are untouched for root D5.

Nuclear bomb and alarm randomness now uses native rolls. Distributions retain five-digit code, distinct three-of-seven wire functions and alarm id 1..9999. The existing native framework uses deterministic instance seeds and preserves map overrides; document that cause in intended_changes.md rather than claiming identical world-RNG realizations. Bomb wires_list is still a fresh mutable seven-key instance list initialized in setup. Cutout constant color=NULL became its type default.

Removed only unused existing init annotations from deleted initializers; no annotations added. Removed inert disabled camera pinboard block counted by the old baseline; live overlay/filter logic unchanged. All debug/world/mapping logging remains.

## Retained sites, reasons

- timeclock ID card (1), magnetic_controller (8): canonical CAPABILITIES blocks are outside A4, in A2 station_ids.dm and admin/magnetic_console_panel.dm respectively. Do not add duplicate blocks. Those owner tasks can declare stamp_initial_job_switch / link_configured_magnets there; their Initializers remain untouched here.

- atm_ret_field (4), firedoor (4): duplicate checks log_mapping at construction and return QDEL. keeps_if only has a WARNING logger; moving side effects into its pure predicate would violate the condition contract and dropping the logger is forbidden. Valid boundary-area registration is a setup job; invalid holders never run it.
- canister (1), portable_atmospherics (3), pump (6), scrubber (4): gas created/fill configured before child init, including the cold-phoron canister outside this scope. Huge pump/scrubber IDs are unique per-instance state. starts/gas-store conversion needs editing existing ownership declarations, reserved by common task rules; converting just one phase would leave null gas in consumers.
- clamp (5), meter (1): constructor target (param) and map-neighbor network/target state; retained exact assignments/calls rather than changing attachment timing.
- camera (10): pre-parent mapped invulnerability/network validation and interning; preserves exact error logging/assert order. HUD installation and post-init upgrades moved into setup.
- clonepod/full (2): dynamic starting biomass contents; converting starts would edit the existing ownership/collection declaration, reserved. No new child-var ownership guessed.
- cryo (1): per-instance direction captured from the mapped facing.
- doorbell (3): constructor building/dir offsets. UID assignment moved into durable setup.
- airlock (3): admin-level secure wiring must be set before parent/capability initialization; close-group join moved into setup.
- angled_bay (1): obtain_icon before parent door geometry; preserve that order.
- blast door (2), base door (16), windowdoor (3): mapped density, opacity, width, access-list and icon-state derived instance state; common door code must precede subclass material/geometry work. Multi-tile opacity publication moved to its own setup hook.
- doppler (9): experiment-handler construction before parent; root D5 owns new-child declarations. World explosion subscription and trait installation moved into setup.
- docking_port (3), docking_port_multi (5): typed program view/name and map-specified child names/tags. Preserve map configuration and initialized child consumers.
- embedded_controller radio (1): set_frequency explicitly must run before parent creates program. No equivalent pre-capability registration form found.
- exonet (3): mapload-only description; sound startup moved into setup.
- frame (15): left untouched for root D5; constructor building/type and ownership site.
- gear_dispenser (6): dynamic datum dictionary content and custom subtype's pre-parent type list. Converting starting dictionary contents requires ownership declaration changes and a keyed/table starting-content contract; common task rules reserve those declarations. Distribution registry and display-door setup moved.
- holoposter (5): mapped forced advert, security-dependent RNG, randomized rotation deadline preserve the existing correlated runtime contract. No persistent shadow roll state introduced.
- machinery base (8), machinery_power (6): constructor dir/mapload and enclosing-location recursive movement setup, whose order precedes specialized Initialize consumers. Common rules forbid rewriting those existing setter/relation declarations.
- navbeacon patrol (1): codes embed the map's next_patrol; retain it before parent. Base turf hiding is setup.
- pipe construction (6): constructor make_from parsing and blueprint effects precede parent initialization; native params currently require a larger consumer migration, not arbitrary setup phase shift.
- protean reconstitutor (2): takes component parts and refreshes before parent. Relation/ownership and parts consumers are reserved; preserve order.
- telecomms presets (10): builds frequency lists before parent (including exclusion parity). Map/per-type listener configuration, not a constant shared mutable list.

## Added tests (unrun; root validates once)

code/modules/unit_tests/dq_a4_initialization_tests.dm
Selectors dq_a4_initialization/* (five tests): real painter instance matrices, actual department announcement/directories and qdel removal, actual bomb code and intact/distinct wire states, actual RCD turret reduced integrity, actual starts-on floodlight with declared cell.

Root owns manifest. Include this file behind the unit-test guard, plus dq_look_pin and appropriate existing machine/door/atmos focused tests. No compile, world, analyzer, generator, baseline update or cargo run by this agent. git diff --check is clean.

## Exact retained site identities

[Committed residual inventory](codex_A4_residual_sites.txt) lists every retained source identity from this lane’s post-edit audit, including repeated normalized rows. The per-file reasons above classify those identities; this is a source audit snapshot, not a fresh analyzer verdict after rebasing. Master’s subsequently removed declarations and rewritten setters must remain authoritative, and the root verification will establish the final baseline counts.

This documentation-only supplement does not change the source proved by stamped commit `b7a1fd8dd9`. No compile, test or generation was rerun for the supplement; documentation-only stamp carry is governed by `agent_workflow.md`.

## Reopened arcade initializer proof

After rebasing onto the read-tracking master, the existing battle arcade `randomize_characters` helper becomes one declared setup job. Correlated cabinet/enemy generation is preserved in the unchanged helper, including its existing RNG calls and runtime round-reset callers. There are no Initialize descendants or ancestor setup jobs; the work is post-parent, does not consume mapload/transient arguments, and still finishes before the constructor returns. Correlated RNG alone was not a valid reason to retain this site.

`dq_a4_initialization/arcade_characters` exercises real construction, checks generated correlated cabinet/enemy names and their actual UI output, and confirms fixed initial combat state remains unchanged. The final exact residual report excludes the removed arcade identity. Additional expected init_lines shrink: one; root analyzer certification is pending.

The original stamped proof `b7a1fd8dd9` predates this source addition and the read-tracking rebase. It does **not** certify the reopened branch. A new full A4 focused proof is pending; no new stamp is claimed here.

Final analyzer update on master a75de08d85: init baseline 4106 ->3900 globally, including the last arcade row. The supported shrink-only update and init lint pass. Current source is not stamped: master compile/DreamChecker/base_vars blockers prevent the required new focused proof.

Tracking follow-up after the read-driven master merge: two moved writes in camera autonaming and point-defense identity cleanup now use their existing generated setters. One remaining finding is outside A4 files: antagonist_create.dm:69 assigns nuke.r_code directly. The native nuclear-code rolls entry makes that field tracked. The caller needs nuke.set_r_code(code), but this task's explicit file scope does not authorize editing the antagonist consumer. This is a lane integration dependency, not an unchanged-master failure; no baseline or ALLOW workaround was added.


## Continuation on 2026-10-15

Rebased cleanly onto origin/master 4ab2e15fe1, preserving master's tracking, setter and ownership changes. The narrowly authorized antagonist consumer now writes the nuclear code through nuke.set_r_code(code); no other antagonist or out-of-scope production code was changed. This resolves the previously documented raw-code-write dependency without an annotation or baseline increase. The setter is generated from the native rolls declaration for r_code.

No generation, analyzer, compile or test has been run on this rebased tip during this continuation. Verification is pending the exclusive B-lane verification queue. Earlier stamps are historical and do not certify this source tip.
