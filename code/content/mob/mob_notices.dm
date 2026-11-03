// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// The `carbon_slip` occurrence (it was an om event).
ACTION(carbon_slip, slipped_on, stun_duration, FIXED, notice = /datum/notice/carbon_slip)

/// NON TG Signals When the mob's dna and species have been fully applied
ACTION(human_dna_finalized, FIXED, notice = /datum/notice/human_dna_finalized)

/// From end of revival_healing_action(): ()
ACTION(living_aheal, FIXED, notice = /datum/notice/living_aheal)

/// From /mob/proc/death(), once per death, after EVERY death side effect (on_death(), HUD refresh, antag win check): (gibbed). Never sent on a repeated or replaced death. Hang end-of-death work (delete_on_death) here; death() itself never deletes the mob.
ACTION(living_death_final, gibbed, FIXED, notice = /datum/notice/living_death_final)

/// From /mob/living/proc/return_from_death(), after the mob is alive again: (datum/source, reason)
ACTION(living_revived, source_, revive_reason, FIXED, notice = /datum/notice/living_revived)
