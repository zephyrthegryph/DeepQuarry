# A11 initialization sweep

Branch `codex/A11`, WT `E:/projects/dq-wt/codex-A11`, base `d36a5946fb`.

28 production files plus one six-test fixture. Source identity estimate: init_lines 229 -> 131 (98 removed), world_reads 9 -> 4. Root must certify with analyzer; no baseline edits. The estimate includes the six manual techweb_node/proc/Initialize rows, whose canonical semantic owner is /datum/techweb_node.

## Migrated work

- Atmos runtime pipe/manifold/vent renderer reset (preserving map editor defaults), vent volume/scrub-gas defaults; algae farm direction description + starting parts, turbine gas ratio/port axes, motor adjacency connection, shutoff open/hide/leak initialization, freezer/heater starting parts, gas-overlay plane positioning.
- Changeling: grown arm creator/message, parent soft suit and armored child formation messages, electric hand sparks/message and finger lockpick message. Parent suit formation remains before child armor formation.
- Cult: Nar-Sie announcement, animation, once-per-world hell state and delayed-evac flag; rune blood image/silicon projection; tome shared cult dictionary lookup. Global cult-word bootstrapping remains in the existing helper; not turned into independent per-instance RNG.
- Meteor spinning + original z capture, technomancer catalog existing set_up() and disturbance's existing radiate_loop() startup.
- Research: post-map-store fabrication parts/RefreshParts setup; destructive analyzer post-handler parts + blocker trait; mech fabrication parts and initial research binding; initial console and server-control links. Pre-parent constructor-store/event-handler work remains.
- Message server uses native rolls for its three-part decryption key, with exactly the old prefix/suffix/digit tables, followed by its exact startup message.
- Technology disk jitter uses PIXEL_JITTER(nameof(randpixel)), preserving its configurable range (5 on the real type). Its research store and debug-store selection remain in their old constructor order.

Native setup and rolls definitions and existing examples checked. No new/shadow state or alias. Existing ordinary setter lines and TRACKED/ownership/reference declarations retained unchanged. The genuine catalog set_up() method is reused via setup(PROC_REF(set_up)); its old invocation disappears, but this is not a registered field setter. Three pipe renderer blocks were added; canonical-block audit must be repeated by root on its combination. Six moved raw icon=null writes use existing set_icon(null); all pre-existing setters remain unchanged.

Order proof: full-tree audit found no remaining Initialize descendants of types migrated in full. The three partially migrated research machinery types also have no descendant initializers. Their materials/handler creation stays before parent initialization; only phase-independent jobs after ..() move to setup. R&D base/server initialization stays unchanged because subclasses consume its connection before a parent post-chain hook could run. Nar-Sie's calls_evac is set in setup before the declared after_init phase.

## Native-roll causes for intended_changes.md (root-owned)

- `/obj/machinery/message_server`: same independent word + word + digit distributions, now per-instance deterministic stream; explicit map/param key overrides survive under native rolls, whereas legacy Initialize overwrote them.
- `/obj/item/disk/tech_disk`: same configured +/- randpixel jitter, now native seeded stream; map offsets remain overrides. Debug-store constructor ordering unchanged.

## Complete retained cohorts

Every retained fingerprint and constructor body is in remaining-text-audit.txt.

- Atmos base: pipe_color snapshots map color, validates it and initializes directions before binary/unary/pipe child initializers use that state. Parent post-chain migration would reverse those consumers. Existing pipe-color setters remain byte-identical.
- Pipe: ensure_pump_materials runs before ancestor initialization; wall/turf level snapshot likewise precedes parent work. Two same-type pipe Initialize definitions need coordinated declaration/parent work; not reordered here.

- Omni base/mixer: creates ordered ports from map tag directions before mixer initializes each port's concentration. Correct starts requires port constructor args and protected ownership declaration changes; moving only base overwrites/omits child work. Constructor map concentration tables retained.
- Hotspot: constructor volume/temperature/cold-fire, adjacent group merge, perform_exposure reentrant spawning/QDEL guards, conditional direction RNG and turf cooldown work form one validity protocol. A post-chain hook must not run on discarded/replaced hotspots; new placement/group declarations needed instead of blanket rename.
- Open turf: setup_open_air before parent, register_open_air after parent also supports the prototype table initialization path. Keep its framework phase contract.
- Changeling ID: constructor mob binding and access clearing depend on inherited ID setup; protected reference/access declaration work remains to migrate.
- Construct spell and base technomancer spell: owner/core validity guards must return QDEL, with existing refusal message retained. These are genuine constructor validation.
- Aura/radiance/flame tongue/reflect: parent spell validity can return QDEL but legacy child logging/messages/welder activation/expiration still run before that hint is processed. Moving only children to setup would suppress those consequences and change logging. Retained as a coordinated spell-lifecycle cohort.
- Control spell: overlay image exists before parent initialization; ownership/starts requires protected declaration changes.
- Blackbox: singleton duplicate guard and immediate GLOB.blackbox registration are a constructor validity/registration contract, not a delayed job. A declared singleton form must replace both together.
- Tech disk: first store creation and debug/admin store override are proto ownership, not per-instance setup; native starts changes protected ownership. Jitter alone migrated.
- R&D production and mech fabricator: mapload is a real remote-materials constructor argument; pre-parent list setup precedes inherited callbacks. Stores remain ordered; post-parent jobs migrated.
- Destructive analyzer: pre-parent experiment-handler creation installs event subscriptions before parent callbacks. Native starting handler requires argument/event policy and ownership declaration changes; post-parent part/trait work migrated.
- R&D base/server: inherited techweb connection callbacks plus server registration must complete before child code; server's correlated random name suffix occurs after registration. Preserve old connection/RNG sequence until those contracts migrate together.
- Techweb node Initialize(): explicitly callable algorithm makes prereq/design/unlock lists associative. This is not atom InitAtom setup; migrating it to New/setup changes callers that invoke normalization after constructing/editing tables.

## Root verification

No builds, tests, generation, baseline/manifest edits, commits or push performed. git diff --check clean. Root should add `#include "code\modules\unit_tests\dq_a11_initialization_tests.dm"`.
Run `/datum/unit_test/dq_a11_initialization` (turbine_ports, message_server, changeling_creator, research_disk, gas_plane, pipe_and_vent_rendering), plus required `dq_look_pin`.

Pipe renderer jobs intentionally keep compile-time map icons and hidden alpha hints while applying runtime resets at setup, exactly as old Initialize did. A base default alone would leave child/map values unchanged. The new constructor test asserts hidden alpha 128 becomes runtime 255 and checks real vent volume.

Root preflight: generated trackedcheck clean; analyzer init baseline4115 ->4012 (103removed), decl47unchanged. Manual techweb-node callbacks remain unchanged. Native-roll causes are recorded in intended_changes.md. Runtime gate pending.

## Exact retained site identities

[Committed residual inventory](codex_A11_residual_sites.txt) lists every retained source identity from this lane’s post-edit audit, including repeated normalized rows. The per-file reasons above classify those identities; this is a source audit snapshot, not a fresh analyzer verdict after rebasing. Master’s subsequently removed declarations and rewritten setters must remain authoritative, and the root verification will establish the final baseline counts.


Source audit repair (2026-10-15): the newly added setup declarations referenced inherited procs with PROC_REF, which checks a current-type proc path. Changed only these new hook references to TYPE_PROC_REF at the actual defining ancestor: `/obj/machinery/atmospherics/unary/freezer` → `/obj/machinery::default_apply_parts`; `/obj/machinery/atmospherics/unary/heater` → `/obj/machinery::default_apply_parts`. Hook names and dynamic dispatch remain unchanged; no wrappers, declarations, setters or behavior changed. No generation, analyzer, compile or test was run for this source-only repair. Verification remains with the A coordinator.
