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
	modifier_type = /datum/body_effect/technomancer/mend_life
	modifier_duration = 10 SECONDS

/datum/body_effect/technomancer/mend_life
	tick_interval = 2 SECONDS
	name = "mend life"
	desc = "You feel rather refreshed."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_warning("Sparkles begin to appear around you, and you feel really.. refreshed.")
	on_expired_text = span_notice("The sparkles have faded, although you feel healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/technomancer/mend_life/on_tick(mob/living/L)
	var/spell_power = spell_power_of(L)
	// Organic mending only: the treatment tags themselves leave synthetic parts alone.
	// Should heal roughly 20 burn/brute over 10 seconds, as tick() is run every 2 seconds.
	var/mended = L.mend(TREAT_TISSUE_REPAIR, 4 * spell_power)
	mended += L.mend(TREAT_BURN_CARE, 4 * spell_power)
	if(!mended) // No point existing if the spell can't heal.
		L.end_body_effect(type)
		return
	L.adjust_instability(1)
	var/mob/living/caster = L.body_effect_origin(type)
	if(istype(caster))
		caster.adjust_instability(1)
