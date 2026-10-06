/datum/body_effect/feysight
	tick_interval = 2 SECONDS
	name = "feysight"
	desc = "You are filled with an inner peace, and widened sight."
	client_color = "#42e6ca"

	on_created_text = span_alien("You feel an inner peace as your mind's eye expands!")
	on_expired_text = span_notice("Your sight returns to what it once was.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_ACCURACY = -15, BF_DISPERSION = 1)

/datum/body_effect/feysight/on_start(mob/living/L)
	L.see_invisible = 60
	L.set_see_invisible_default(60)
	L.vis_enabled += VIS_GHOSTS
	L.recalculate_vis()

/datum/body_effect/feysight/on_end(mob/living/L, expired)
	L.set_see_invisible_default(initial(L.see_invisible_default))
	L.see_invisible = L.see_invisible_default
	L.vis_enabled -= VIS_GHOSTS
	L.recalculate_vis()

/datum/body_effect/feysight/can_apply(mob/living/L)
	if(L.stat)
		to_chat(L, span_warning("You can't be unconscious or dead to experience tranquility."))
		return FALSE

	if(!L.is_sentient())
		return FALSE // Drones don't feel anything.

	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if(H.species?.mood_immune)
			to_chat(L, span_warning("You feel strange for a moment, but it passes."))
			return FALSE // Happy trees aren't affected by tranquility.

	return ..()

/datum/body_effect/feysight/on_tick(mob/living/L)
	..()

	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		H.status_set(STAT_DRUGGED, min(15, H.status_units(STAT_DRUGGED) + 4))
