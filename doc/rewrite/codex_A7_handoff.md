# A7 handoff: clothing and turfs

Branch `codex/A7`, worktree `E:/projects/dq-wt/codex-A7`, base `219f9ef940`.

24 production files changed, one new five-test fixture. Analyzer confirmed: init_lines249→161 (88 removed),world_reads9→6 (3 removed);91 total removed.

Declared setup jobs now cover collar radio connection, dosimeter film, tags holder identity, material bracelet/ring display after validated material resolution, shoes movement emotes, Ranger naming, mech/clown squeak setup, exact-type helmet refit, RIG system settings/component registry orchestration, valid stat-module button labels, crusher storage links, datajack list allocation, self-destruct smoke attachment, landed-holder placement capture, shuttle light cache plus wall join, alien floor lights, nanite water SMES lookup, sky glow, planetary turf registration, skyfall adjacency glow, lava audio, and transit animation direction. All reused master setup(PROC_REF()) and existing hook bodies. No new state or aliases.

Order checks:
- Ancestor shoe emotes and descendant Ranger names moved together: ancestor setup captures the uncoloured initial name before descendant naming, as before. Outside A7 shoe overrides (/none and /circuitry) do not change that name or consume movement emotes during construction.
- Shuttle antlight cache and wall joins moved together; ancestor cache setup runs before wall joins. Other shuttle descendants have no intervening Initialize consumers. Alien floor lighting remains after its ancestor work.
- RIG settings are copied before component_registry.initialize_pieces(), unchanged. No /rig descendants override Initialize. Existing ownership starts have already supplied the subsystems.
- Material resolution and invalid-material deletion remain in Initialize; setup does not run for the discarded item.
- Button module binding/type guards remain in Initialize; labels only run for valid modules.
- Pre-parent lava outdoors/name/light work remains; only audio starts move.
- Existing TRACKED, ownership/reference declarations and setter-call text are unchanged. No replacement writes needed.

## Retained groups (all remaining identity rows appear in remaining-text-audit.txt)

- `/obj/item/clothing`: starting accessory creation/attachment needs starts with an attachment policy, requiring a protected ownership declaration change. Existing empty set_clothing_index() call left byte-identical under the setter-call scope restriction.
- `/clothing/ears/offear`: constructor-location object appearance copy, including registered set_dir. Its owner can be a partially initialized object; delaying that snapshot would change which appearance is captured.
- `/clothing/suit`: MakeHood and toggle icon happen before ancestor initialization; cannot delay without changing subsequent parent/child constructor behaviour.
- `/clothing/under`: worn_state/map sprite detection and initial owner sensor preference are per-instance. Random sensor choice depends on a real human owner; preserve invalid-preference logging. No declarative conditional multi-field owner-context roll demonstrated.
- Material ring/bracelet: forced-material default before parent, resolved material type guard after parent. Kept constructor validity order; display assignments moved.
- Accessory storage base, knifeharness and vox: base capacity/on_rolled must precede child overrides and child starting knives. Moving base alone overwrites child capacity; moving children requires protected ownership/starts declarations. Retained coordinated group.
- Space suit: two same-type Initialize definitions in spacesuits.dm and breaches.dm; remembers map/loadout name before future breach modification. Retained until chain semantics and subclass naming snapshots can be migrated together; no second CAPABILITIES block.
- RIG module base: conditional overlay setter plus construction of charge datums and charge selection; descendants use those objects. Kept protected setter and construction order.
- Stat module base/activate/deactivate/engage: constructor-location typed link and invalid-parent deletion guards; only display naming moved.
- RIG vision: per-instance owned mode creation and selection involves protected relation mutation declarations; no declaration changes here.
- `/turf`: shared prototype-table initialization fast path; keep constructor/map semantics and existing framework initializer unchanged.
- `/turf/simulated`: area holiness, level update, outdoor membership require canonical declaration block outside A7 (sunlight_handler.dm). Do not add a duplicate block.
- Seasonal/grass/sif/rocks: pre-parent density-gated peer spawn order and seasonal branching affects next density check and parent spawning; winter can chill into a different turf. Cannot delay into post-chain setup safely or roll independent fields without changing RNG coupling. The remaining world-read rows are mapped in the exact inventory below.
- Fancy shuttle: INITIALIZE_IMMEDIATE helper records coordinate/icon data before shuttle walls construct; post-chain setup can run too late. Preserve mapping-error log and cache order.
- Floor: ephemeral floortype_at_make constructor input is not guaranteed available after setup; floor install must precede subclass code. Dirt choice/material-dependent draw occurs after floor install and before descendants.
- Lava: pre-parent outdoors-derived name and light retained, audio migrated.
- Water: handle_fish performs density/random conditional peer spawning. Native spawn-table migration needs a coupled world-context policy, not blanket setup relocation.
- Space: appearance before parent protects prototype-table/built-space parity.

## Verification delegated to root

No builds, tests, generation, baseline updates, manifest edits, commits, merge or push run here. git diff --check is clean. Cross-tree audit of 14 newly introduced CAPABILITIES blocks found no duplicates. Protected declaration/setter text comparison clean after preserving set_clothing_index().

Add `#include "code\modules\unit_tests\dq_a7_initialization_tests.dm"` to the root-owned manifest. Focus `/datum/unit_test/dq_a7_initialization` (five leaves: ranger_ancestor_order, material_identity, datajack_storage, rig_systems, helmet_refit) plus requested `dq_look_pin`.

Analyzer certified global init4115→4024 (91 removed); scoped counts249→161 and9→6 are confirmed. Decl47→46, tracked clean after generation. Moved wall icon_state and RIG item_state now use existing registered setters; no pre-existing setter or declaration changed.

## Exact retained site identities

[Committed residual inventory](codex_A7_residual_sites.txt) lists every retained source identity from this lane’s post-edit audit, including repeated normalized rows. The per-file reasons above classify those identities; this is a source audit snapshot, not a fresh analyzer verdict after rebasing. Master’s subsequently removed declarations and rewritten setters must remain authoritative, and the root verification will establish the final baseline counts.

## Additional ordered setup jobs after review

Fishing hats now declare the existing `roll_slogan` followed by `apply_look` as two ordered setup entries. The helpers, RNG sequence, existing appearance setters and correlated slogan/size/hue generation remain unchanged. Neither the parent Initialize chain nor a descendant consumes the result before setup; no Initialize descendant exists. The item’s other capability entries do not add an intervening setup job. This was avoidable residual work, not a correlated-RNG form gap.

Dark floor tiles declare the original post-parent 5% glow decision as one setup job. They have no Initialize descendants, no ancestor setup jobs and no RNG-consuming parent path (no flooring and `can_dirty = FALSE`). The existing runtime Crossed path and glow image builder remain unchanged. No mapload/transient parameter is consumed by the moved work, and both types retain the inherited `init_from_table = FALSE`; no table fast path is activated by this change.

Two constructor regressions were added: `dq_a7_initialization/fishing_slogan` checks the real correlated text, hue, size and icon values; `dq_a7_initialization/dark_glow` selects and replays real RNG seeds for both conditional construction outcomes, checks actual overlays, and defers restoration of the changed turf before creating it. Estimated additional shrink: four init_lines identities and one world_reads row; analyzer certification is pending.
