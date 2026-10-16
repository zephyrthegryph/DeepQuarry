# VR pair sparse-link handoff

This source-only follow-up removes two base fields, `vr_holder` and `vr_link`, preserving their reciprocal borrowed identity in a declared sparse native link. Neither replacement, clear nor endpoint deletion destroys the other mob. This brings the human-path source cohort to 30 of 44 fields converted; analyzer counts and runtime proof remain pending.

The complete production consumer audit found only uncached effects and periodic work: enter/exit/reuse VR, sleeper exit/dematerialization, death/gib/ghostize and transcore implant processing. None is a reactive draw, requirement, condition or cached UI reader, so this pair does not depend on a link-publication contract. All reads use typed `get_vr_holder()` / `get_vr_avatar()` accessors. Native link writes replace the original borrowed relation verbs; independent `teleop` bookkeeping and real mind movement stay in place.

## Exact source cohort

* `code/__defines/engine/link_keys.dm`: two VR key constants only.
* `code/library/mob/hands.dm`: replace the existing human VR pair declaration, no second block.
* `code/modules/mob/living/carbon/human/human_defines.dm`: remove the two fields and add the two typed accessors.
* `code/modules/mob/living/carbon/human/death.dm`.
* `code/modules/mob/living/carbon/human/species/virtual_reality/avatar.dm`.
* `code/game/machinery/virtual_reality/vr_console.dm`.
* `code/game/machinery/virtual_reality/ar_console.dm`.
* `code/modules/resleeving/transcore_service.dm`.
* `code/modules/mob/dead/observer/observer.dm`.
* `code/modules/unit_tests/dq_refs_waves_tests.dm`: retain the existing real peer-deletion regression using native APIs.
* New `code/modules/unit_tests/dq_base_vars_vr_link_tests.dm` (root wires include).
* This handoff.

The new leaves `/datum/unit_test/dq_base_vars_vr_links/reciprocal_replace_clear` and `/datum/unit_test/dq_base_vars_vr_links/real_mind_roundtrip` assert replacement/clearing/non-deletion, actual public enter/exit mind transfer, independent teleoperation clearing, remembered avatar identity and real endpoint deletion. Also run existing `dq_refs_vr_pair_links_and_clears` plus mandatory pins.

## Retained references

Six borrowed reactive references stay unchanged: default attack, synthetic model, ear style, secondary ear style, tail style and wing style. Sparse `link_get()` reads `rx.link_ends`; `link_store()`/`link_unstore()` currently mutate that map without publication, the generated `auto_tracked` does not track it, and the analyzer has no `link_get`/`link_make`/`link_set_one` dependency handling. Moving their draw/UI readers would silently lose invalidation. They need a native sparse-link publication and dependency contract, not aliases or manual publishes.

Eight owned references remain exactly as documented in the preceding human handoff: medical effects, wearing rig, glamour rings, genetic effects, shadekin, character forms, trait states and xenochimera. Preserve owned replacement/removal disposal and the rig's contained-only policy before moving them.

Source diff check passed. No generation, analyzer, build, tests, baseline edits or stamp claimed for this follow-up.
