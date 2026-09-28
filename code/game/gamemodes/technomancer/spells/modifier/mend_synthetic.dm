/datum/technomancer/spell/mend_synthetic
	name = "Mend Synthetic"
	desc = "Repairs minor damage to prosthetics.  \
	Instability is split between the target and technomancer, if separate.  The function will end prematurely \
	if the target is completely healthy, preventing further instability."
	spell_power_desc = "Healing amount increased."
	cost = 50
	obj_path = /obj/item/spell/modifier/mend_synthetic
	ability_icon_state = "tech_mendsynth"
	category = SUPPORT_SPELLS

/obj/item/spell/modifier/mend_synthetic
	name = "mend synthetic"
	desc = "You are the Robotics lab"
	icon_state = "mend_synthetic"
	cast_methods = CAST_MELEE
	aspect = ASPECT_BIOMED // sorta??
	light_color = "#FF5C5C"
	modifier_type = /datum/body_effect/technomancer/mend_synthetic
	modifier_duration = 10 SECONDS

/datum/body_effect/technomancer/mend_synthetic
	tick_interval = 2 SECONDS
	name = "mend synthetic"
	desc = "Something seems to be repairing you."
	mob_overlay_state = "cyan_sparkles"

	on_created_text = span_warning("Sparkles begin to appear around you, and your systems report integrity rising.")
	on_expired_text = span_notice("The sparkles have faded, although your systems seem to be better than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/technomancer/mend_synthetic/on_tick(mob/living/L)
	var/spell_power = spell_power_of(L)
	// Synthetic repair only: plating/wiring tags act on synthetic parts (robot limbs, chassis).
	// Should heal roughly 20 burn/brute over 10 seconds, as tick() is run every 2 seconds.
	var/mended = L.mend(TREAT_PLATING_REPAIR, 4 * spell_power)
	mended += L.mend(TREAT_WIRING_REPAIR, 4 * spell_power)
	if(!mended) // No point existing if the spell can't heal.
		L.end_body_effect(type)
		return

	L.adjust_instability(1)
	var/mob/living/caster = L.body_effect_origin(type)
	if(istype(caster))
		caster.adjust_instability(1)
