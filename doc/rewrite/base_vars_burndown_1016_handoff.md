# Base-variable burn-down

Branch: `codex/base-vars-burndown`, based on master c3cb037784.

The starting baseline has 539 rows. The source cohorts are committed separately
by owning subsystem, with consumers updated together. Analyzer reduction and
compilation/runtime proof are pending; source counts are not verification.

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
