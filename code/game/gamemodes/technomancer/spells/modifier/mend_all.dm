// Gambit only spell.  Heals everything unconditionally.

/obj/item/spell/modifier/mend_all
	name = "mend all"
	desc = "One function to heal them all."
	icon_state = "mend_all"
	cast_methods = CAST_MELEE
	aspect = ASPECT_BIOMED
	light_color = "#FF5C5C"
	modifier_type = /datum/modifier/technomancer/mend_all
	modifier_duration = 1 MINUTE

/datum/modifier/technomancer/mend_all
	name = "mend all"
	desc = "You feel serene and well rested."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_warning("Sparkles begin to appear around you, and all your ills seem to fade away.")
	on_expired_text = span_notice("The sparkles have faded, although you feel much healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/modifier/technomancer/mend_all/tick()
	// Should heal roughly 120 damage over 1 minute, as tick() is run every 2 seconds.
	var/mended = holder.mend(TREAT_TISSUE_REPAIR, 4 * spell_power)
	mended += holder.mend(TREAT_PLATING_REPAIR, 4 * spell_power)
	mended += holder.mend(TREAT_BURN_CARE, 4 * spell_power)
	mended += holder.mend(TREAT_WIRING_REPAIR, 4 * spell_power)
	mended += holder.mend(TREAT_ANTITOXIN, 4 * spell_power)
	mended += holder.mend(TREAT_OXYGENATION, 4 * spell_power)
	mended += holder.mend(TREAT_GENETIC_REPAIR, 2 * spell_power) // 60 genetic damage
	if(!mended) // No point existing if the spell can't heal.
		expire()
		return
	holder.adjust_instability(1)
	if(origin)
		var/mob/living/L = origin.resolve()
		if(istype(L))
			L.adjust_instability(1)
