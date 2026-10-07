/datum/technomancer/spell/phase_shift
	name = "Phase Shift"
	desc = "Hides you in the safest possible place, where no harm can come to you.  Unfortunately, a prolonged stay inside the \
	rift you create will afflict you with instability."
	cost = 50
	obj_path = /obj/item/spell/phase_shift
	ability_icon_state = "tech_phaseshift"
	category = DEFENSIVE_SPELLS

/obj/item/spell/phase_shift
	name = "phase shift"
	desc = "Allows you to dodge your untimely fate by shifting your location somewhere else, so long as you can survive inside the \
	rift."
	icon_state = "blink"
	cast_methods = CAST_USE
	aspect = ASPECT_TELE

/obj/item/spell/phase_shift
	light_range = 3
	light_power = 2
	light_color = "#FA58F4"
	light_on = TRUE

/obj/effect/phase_shift
	resistance_flags = BOMB_PROOF
	name = "rift"
	desc = "There was a maniac here a moment ago..."
	icon = 'icons/effects/effects.dmi'
	icon_state = "rift"

/obj/effect/phase_shift
	light_range = 3
	light_power = 5
	light_color = "#FA58F4"
	light_on = TRUE

// whatever phased inside comes back out on the turf.
CAPABILITIES(/obj/effect/phase_shift)
	owns_many(nameof(contents), on_destroy = ON_DESTROY_SPILL)
	every(2 SECONDS, then(PROC_REF(phase_shift_step)))

/// Wears on whoever hides inside every 2 s; empty, the run does nothing.
/obj/effect/phase_shift/proc/phase_shift_step(datum/act/timer/A)
	if(!(locate_within(src, /mob/living)))
		return
	for(var/mob/living/L in contents)
		L.adjust_instability(2)

/obj/effect/phase_shift/relaymove(mob/user as mob)
	if(user.stat)
		return

	to_chat(user, span_notice("You step out of the rift."))
	user.forceMove(get_turf(src))
	spent(src, user)

/obj/item/spell/phase_shift/on_use_cast(mob/user)
	if(isturf(user.loc)) //Check if we're not already in a rift.
		if(pay_energy(2000))
			var/obj/effect/phase_shift/PS = new(get_turf(user))
			act_message(user, null, others = span_warning("%U% vanishes into a pink rift!"))
			to_chat(user, span_info("You create an unstable rift, and go through it.  Be sure to not stay too long."))
			user.forceMove(PS)
			adjust_instability(10)
			consume(src, user)
		else
			to_chat(user, span_warning("You don't have enough energy to make a rift!"))
	else //We're already in a rift or something like a closet.
		to_chat(user, span_warning("Making a rift here would probably be a bad idea."))
