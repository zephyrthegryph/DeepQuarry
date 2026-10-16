# Base-variable burn-down

Branch: `codex/base-vars-burndown`, based on master c3cb037784.

The starting baseline had 539 rows. The analyzer now reports 410: 129 removed, zero added. The source cohorts are committed separately
by owning subsystem, with consumers updated together. Generation and the base_vars check pass, including records_data_only at zero.
Compilation/runtime lane-ready proof remains pending.

Per-cohort handoffs cover lighting, human state, behaviours, last-attacker
links, voice choices and body-effect serials. Other cohorts cover transforms,
emotes, caches, medical cursors, vore options, heat and melee timing.

Remaining reactive flags need sparse-slot key publication and generated read
dependencies. They retain their old fields. Four lighting references need a
phase-aware sparse ownership contract: a naive record would move disposal
from OWNED to LINKS and change the original holder's disposal hook. Owned
human references similarly retain replacement/clear and contained ownership
semantics; no manual qdel glue substitutes for those contracts.

No new ALLOW annotations or baseline additions are included.

The follow-up damage trait and uncached reciprocal VR link cohorts remove five additional rows. Six reactive borrowed human references remain because sparse links do not publish dependency keys; eight owned references retain replacement/clear/contained semantics.

## Unlanded burning conversion withdrawn

Five original master fields remain: burn_overlay, burn_particle_type, burn_fuel, burn_cool_watch and burn_ended_by. Granted capability draw providers are not consumed by the current presentation path, and native granted look layers cannot represent the arbitrary retained mutable appearance accepted by start_burning(). The conversion and its premature five-row baseline removal were backed out. This introduces no master baseline rows: the final baseline is a strict subset of origin/master. The lifetime regression now tests the retained real cooling-watch ownership.

Final source verification: analyze baseline --update --lint base_vars and the full check_ratchets.sh pass at b27c25b5bd. Baseline 539 -> 410; 129 original rows removed, no rows added relative to master. Native compile, DreamChecker and focused lane-ready runtime proof remain pending.

## Final additional cohort

Nine configuration fields (five sound, four butchery) now use copy-on-write native traits, preserving old map/admin names. Three material emission samples and the last tasted text use numeric/text sparse slots; only imperative readers consume them. Native generator and all ratchets pass at 419a5b09bb. The baseline is 539 -> 410, 129 removed and zero added relative to master. say_list_type remains because the existing mecha roll requires a physical target field. Runtime verification is still pending; no stamp is claimed.
