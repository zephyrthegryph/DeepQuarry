/obj/item/projectile/beam/lightning/slime
	power = 10
	fire_sound = SFX_EFFECTS_LIGHTNINGBOLT

/datum/body_effect/aura/slime_heal
	tick_interval = 2 SECONDS
	name = "slime mending"
	desc = "You feel somewhat gooey."
	mob_overlay_state = "pink_sparkles"
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 2

	on_created_text = span_warning("Twinkling spores of goo surround you.  It makes you feel healthier.")
	on_expired_text = span_notice("The spores of goo have faded, although you feel much healthier than before.")

/datum/body_effect/aura/slime_heal/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

	if(ishuman(L)) // Every limb, organic or robotic.
		var/mob/living/carbon/human/H = L
		for(var/obj/item/organ/external/E as anything in H.organs)
			H.mend(TREAT_TISSUE_REPAIR, 1, E.organ_tag)
			H.mend(TREAT_BURN_CARE, 1, E.organ_tag)
			H.mend(TREAT_PLATING_REPAIR, 1, E.organ_tag)
			H.mend(TREAT_WIRING_REPAIR, 1, E.organ_tag)
	else
		L.mend(TREAT_TISSUE_REPAIR, 1)
		L.mend(TREAT_BURN_CARE, 1)
		L.mend(TREAT_PLATING_REPAIR, 1)
		L.mend(TREAT_WIRING_REPAIR, 1)

	L.mend(TREAT_ANTITOXIN, 2)
	L.mend(TREAT_OXYGENATION, 2)
	L.mend(TREAT_GENETIC_REPAIR, 1)
