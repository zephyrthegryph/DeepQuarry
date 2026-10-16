# Base-variable burn-down

Branch: `codex/base-vars-burndown`, based on master c3cb037784.

The starting baseline had 539 rows. The analyzer now reports 418: 121 removed, zero added. The source cohorts are committed separately
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
