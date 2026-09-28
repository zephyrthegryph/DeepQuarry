// Gambit only spell.  Heals everything unconditionally.

/obj/item/spell/modifier/mend_all
	name = "mend all"
	desc = "One function to heal them all."
	icon_state = "mend_all"
	cast_methods = CAST_MELEE
	aspect = ASPECT_BIOMED
	light_color = "#FF5C5C"
	modifier_type = /datum/body_effect/technomancer/mend_all
	modifier_duration = 1 MINUTE

/datum/body_effect/technomancer/mend_all
	tick_interval = 2 SECONDS
	name = "mend all"
	desc = "You feel serene and well rested."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_warning("Sparkles begin to appear around you, and all your ills seem to fade away.")
	on_expired_text = span_notice("The sparkles have faded, although you feel much healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/technomancer/mend_all/on_tick(mob/living/L)
	var/spell_power = spell_power_of(L)
	// Should heal roughly 120 damage over 1 minute, as tick() is run every 2 seconds.
	var/mended = L.mend(TREAT_TISSUE_REPAIR, 4 * spell_power)
	mended += L.mend(TREAT_PLATING_REPAIR, 4 * spell_power)
	mended += L.mend(TREAT_BURN_CARE, 4 * spell_power)
	mended += L.mend(TREAT_WIRING_REPAIR, 4 * spell_power)
	mended += L.mend(TREAT_ANTITOXIN, 4 * spell_power)
	mended += L.mend(TREAT_OXYGENATION, 4 * spell_power)
	mended += L.mend(TREAT_GENETIC_REPAIR, 2 * spell_power) // 60 genetic damage
	if(!mended) // No point existing if the spell can't heal.
		L.end_body_effect(type)
		return
	L.adjust_instability(1)
	var/mob/living/caster = L.body_effect_origin(type)
	if(istype(caster))
		caster.adjust_instability(1)
