/datum/technomancer/spell/purify
	name = "Purify"
	desc = "Clenses the body of harmful impurities, such as toxins, radiation, viruses, genetic damage, and such.  \
	Instability is split between the target and technomancer, if separate.  The function will end prematurely \
	if the target is completely healthy, preventing further instability."
	spell_power_desc = "Healing amount increased."
	cost = 25
	obj_path = /obj/item/spell/modifier/purify
	ability_icon_state = "tech_purify"
	category = SUPPORT_SPELLS

/obj/item/spell/modifier/purify
	name = "mend life"
	desc = "Watch your wounds close up before your eyes."
	icon_state = "mend_life"
	cast_methods = CAST_MELEE
	aspect = ASPECT_BIOMED
	light_color = "#FF5C5C"
	modifier_type = /datum/body_effect/technomancer/purify
	modifier_duration = 10 SECONDS

/datum/body_effect/technomancer/purify
	tick_interval = 2 SECONDS
	name = "purify"
	desc = "You feel rather clean and pure."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_warning("Sparkles begin to appear around you, and you feel really.. pure.")
	on_expired_text = span_notice("The sparkles have faded, although you feel healthier than before.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/technomancer/purify/on_tick(mob/living/L)
	var/spell_power = spell_power_of(L)
	if(!L.mend(TREAT_ANTITOXIN, 4 * spell_power)) // Should heal roughly 120 damage over 1 minute, as tick() is run every 2 seconds.
		L.end_body_effect(type) // No point existing if the spell can't heal.
		return
	L.adjust_instability(1)
	var/mob/living/caster = L.body_effect_origin(type)
	if(istype(caster))
		caster.adjust_instability(1)
