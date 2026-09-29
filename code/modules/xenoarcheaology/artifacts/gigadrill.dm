/obj/machinery/giga_drill
	name = "alien drill"
	desc = "A giant, alien drill mounted on long treads."
	icon = 'icons/obj/mining.dmi'
	icon_state = "gigadrill"
	active = 0
	var/drill_time = 10
	var/tmp/turf/drilling_turf
	density = TRUE
	layer = ABOVE_JUNK_LAYER

/obj/machinery/giga_drill/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/giga_drill_toggle,
	)
	..()

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/giga_drill_toggle
	id = "giga_drill_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/giga_drill/proc/interaction_toggle

/obj/machinery/giga_drill/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(active)
		set_active(0)
		icon_state = "gigadrill"
		to_chat(user, span_notice("You press a button and \the [src] slowly spins down."))
	else
		set_active(1)
		icon_state = "gigadrill_mov"
		to_chat(user, span_notice("You press a button and \the [src] shudders to life."))
	return TRUE

/obj/machinery/giga_drill/Bump(atom/A)
	if(active && !drilling_turf())
		if(ismineralturf(A))
			var/turf/simulated/mineral/M = A
			rel_set(src, "drilling_turf", get_turf(src))
			src.visible_message(span_bold("\The [src]") + " begins to drill into \the [M].")
			set_anchored(TRUE)
			om_after(src, drill_time, PROC_REF(finish_drilling), M)

/obj/machinery/giga_drill/proc/finish_drilling(turf/simulated/mineral/M)
	if(get_turf(src) == drilling_turf() && active)
		M.GetDrilled()
		src.forceMove(M)
	rel_clear(src, "drilling_turf")
	set_anchored(FALSE)

/// Accessor for the drilling_turf var.
/obj/machinery/giga_drill/proc/drilling_turf() as /turf
	return drilling_turf
