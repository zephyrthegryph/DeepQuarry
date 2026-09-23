/datum/technomancer/spell/mend_life
	name = "Mend Life"
	desc = "Heals minor wounds, such as cuts, bruises, burns, and other non-lifethreatening injuries.  \
	Instability is split between the target and technomancer, if separate.  The function will end prematurely \
	if the target is completely healthy, preventing further instability."
	spell_power_desc = "Healing amount increased."
	cost = 50
	obj_path = /obj/item/spell/modifier/mend_life
	ability_icon_state = "tech_mendwounds"
	category = SUPPORT_SPELLS

/obj/item/spell/modifier/mend_life
	name = "mend life"
	desc = "Watch your wounds close up before your eyes."
	icon_state = "mend_life"
	cast_methods = CAST_MELEE
	aspect = ASPECT_BIOMED
	light_color = "#FF5C5C"
	modifier_type = /datum/modifier/technomancer/mend_life
	modifier_duration = 10 SECONDS

/datum/modifier/technomancer/mend_life
	name = "mend life"
	desc = "You feel rather refreshed."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_warning("Sparkles begin to appear around you, and you feel really.. refreshed.")
	on_expired_text = span_notice("The sparkles have faded, although you feel healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/modifier/technomancer/mend_life/tick()
	// Organic mending only: the treatment tags themselves leave synthetic parts alone.
	// Should heal roughly 20 burn/brute over 10 seconds, as tick() is run every 2 seconds.
	var/mended = holder.mend(TREAT_TISSUE_REPAIR, 4 * spell_power)
	mended += holder.mend(TREAT_BURN_CARE, 4 * spell_power)
	if(!mended) // No point existing if the spell can't heal.
		expire()
		return
	holder.adjust_instability(1)
	if(origin)
		var/mob/living/L = origin.resolve()
		if(istype(L))
			L.adjust_instability(1)
