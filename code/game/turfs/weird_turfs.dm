/turf/simulated/floor/weird_things
	icon = 'icons/turf/flooring/weird_vr.dmi'

/turf/simulated/floor/weird_things/dark
	name = "dark"
	desc = "It's a strange, impenetrable darkness."
	icon_state = "dark"
	can_dirty = FALSE

/turf/simulated/floor/weird_things/dark/Initialize(mapload)
	. = ..()
	if(prob(5))
		add_glow()

/turf/simulated/floor/weird_things/dark/Crossed(O)
	. = ..()
	if(!isliving(O))
		return
	cut_overlays()
	if(prob(5))
		add_glow()
	if(ishuman(O))
		var/mob/living/carbon/human/L = O
		if(istype(L.species, /datum/species/crew_shadekin))
			L.injure(INJURY_PAIN, 5, null, src, 0, null, INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
			if(prob(50))
				to_chat(L, span_danger("The more you move through this darkness, the more you can feel a throbbing, shooting ache in your bones."))
			if(prob(5))
				L.visible_message("[L]'s body gives off a faint, sparking, haze...", "Your body gives off a faint, sparking, haze...", runemessage = "gives off a faint, sparking haze")
		var/datum/component/shadekin/comp = L.GetComponent(/datum/component/shadekin)
		if(comp)
			comp.dark_energy += 10
			if(prob(10))
				to_chat(L, span_notice("You can feel the energy flowing into you!"))
		else if(prob(0.25))
			to_chat(L, span_danger("The darkness seethes under your feet..."))
			L.status_adjust(EFFECT_HALLUCINATING, 50)

/turf/simulated/floor/weird_things/dark/proc/add_glow()
	var/choice = "overlay-[rand(1,6)]"
	var/image/i = image('icons/turf/flooring/weird_vr.dmi', choice)
	i.plane = PLANE_LIGHTING_ABOVE
	add_overlay(i)

