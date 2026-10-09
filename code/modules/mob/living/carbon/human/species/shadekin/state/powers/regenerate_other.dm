//////////////////////////
///  REGENERATE OTHER  ///
//////////////////////////
// Shadekin powers that spend energy on themselves or a neighbour (create_shade.dm is the other one). Regenerate other is a targeted ability:
// it asks which creature next to you to mend, the way the legacy verb did, and checks the pick again when the answer lands.

MSG_DEF_SELF(shadekin_ability/nobody_near, "There's nothing nearby to regenerate other.")

CAPABILITY_DEF(shadekin_utility, CAP_SHADEKIN_UTILITY, key = NONE)

/datum/capability/def/shadekin_utility/entries()
	return list(
		op("regenerate_other", label("Regenerate other"), menu(button = "Regenerate other", bind = "ability_shadekin_regenerate_other"),
			needs(req_conscious(),
				req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin)),
				req(TYPE_PROC_REF(/mob/living, ability_not_shifted), because = MSG(shadekin_ability/phase_shifted)),
				req(TYPE_PROC_REF(/mob/living, ability_can_afford_50), because = MSG(shadekin_ability/low_energy)),
				req(TYPE_PROC_REF(/mob/living, ability_has_regenerate_candidates), because = MSG(shadekin_ability/nobody_near))),
			asks(/datum/prompt/choice/ability_pick, fields = list("title" = "Regenerate other", "question" = "Mend whom?", "choices" = computed(TYPE_PROC_REF(/mob/living, ability_regenerate_candidate_choices))), step = "target"),
			then(TYPE_PROC_REF(/mob/living, ability_regenerate_other))),
		op("create_shade", label("Create shade"), menu(button = "Create shade", bind = "ability_shadekin_create_shade"),
			needs(req_conscious(),
				req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin)),
				req(TYPE_PROC_REF(/mob/living, ability_not_shifted), because = MSG(shadekin_ability/phase_shifted)),
				req(TYPE_PROC_REF(/mob/living, ability_can_afford_25), because = MSG(shadekin_ability/low_energy))),
			then(TYPE_PROC_REF(/mob/living, ability_create_shade))))

/// The creatures next to the actor, never the actor (the legacy oview(1) list).
/mob/living/proc/regenerate_candidates()
	. = list()
	for(var/mob/living/L in oview(1, src))
		. += L

/mob/living/proc/ability_has_regenerate_candidates(datum/act/op/A)
	return length(regenerate_candidates()) > 0

/mob/living/proc/ability_regenerate_candidate_choices(datum/act/op/A)
	return regenerate_candidates()

/mob/living/proc/ability_can_afford_50(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return !!SK && SK.shadekin_get_energy() >= 50

/// Mends the picked creature, announced by the shadekin.
/mob/living/proc/ability_regenerate_other(datum/act/op/A)
	var/mob/living/target = A.step_value("target")
	if(!istype(target) || !(target in regenerate_candidates()))
		return OP_FAILED
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	SK.shadekin_adjust_energy(-50)
	play_sfx(src, SFX_EFFECTS_EMPULSE, 0.75)
	target.apply_body_effect(/datum/body_effect/shadekin/heal_boop, 1 MINUTE)
	act_message(src, target, others = span_notice("%U% gently places a hand on %T%..."))
	face_atom(target)
	return OP_OK

/datum/body_effect/shadekin/heal_boop
	tick_interval = 2 SECONDS
	name = "Shadekin Regen"
	desc = "You feel serene and well rested."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_notice("Sparkles begin to appear around you, and all your ills seem to fade away.")
	on_expired_text = span_notice("The sparkles have faded, although you feel much healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/shadekin/heal_boop/on_tick(mob/living/L)
	var/mended = L.mend(TREAT_TISSUE_REPAIR, 2)
	mended += L.mend(TREAT_BURN_CARE, 2)
	mended += L.mend(TREAT_ANTITOXIN, 2)
	mended += L.mend(TREAT_OXYGENATION, 2)
	mended += L.mend(TREAT_GENETIC_REPAIR, 2)
	if(!mended) // No point existing if the spell can't heal.
		L.end_body_effect(type)
		return
