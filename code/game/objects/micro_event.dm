/obj/structure/portal_event/resize
	name = "portal"
	desc = "It leads to someplace else!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "type-d-portal"
	var/shrinking = TRUE
	var/size_limit = 0.5

CAPABILITIES(/obj/structure/portal_event/resize)
	op("portal_resize_settings", observer(), priority(OP_PRIORITY_NORMAL + 2), when(req_empty(nameof(target)), req_rights(R_HOLDER)), passes(), 		asks(/datum/prompt/choice, fields = list("title" = "Change portal size settings", "question" = "Would you like to adjust the portal's size settings?", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "adjust"), 		asks(/datum/prompt/choice, fields = list("title" = "Change portal size settings", "question" = "Should this portal shrink people who are over the limit, or grow people who are under the limit?", "choices" = list("Shrink", "Grow"), "buttons" = TRUE, "timeout" = 0), step = "mode", when = PROC_REF(size_adjusting)), 		asks(/datum/prompt/number, fields = list("title" = "Pick a Size", "question" = computed(PROC_REF(size_limit_question)), "default" = 1, "min_value" = 0, "max_value" = INFINITY, "timeout" = 0), step = "limit", when = PROC_REF(size_adjusting)), 		then(PROC_REF(apply_size_settings)))

/// Staff said yes to adjusting the size settings.
/obj/structure/portal_event/resize/proc/size_adjusting(datum/act/op/A)
	return A.step_value("adjust") == "Yes"

/// The size limit question, worded for the mode picked.
/obj/structure/portal_event/resize/proc/size_limit_question(datum/act/op/A)
	if(A.step_value("mode") == "Shrink")
		return "What should the size limit be? Anyone over this limit will be shrunk to this size. (1 = 100%, etc)"
	return "What should the size limit be? Anyone under this limit will be grown to this size. (1 = 100%, etc)"

/// The size settings staff picked (nothing when they declined).
/obj/structure/portal_event/resize/proc/apply_size_settings(datum/act/op/A)
	if(A.step_value("adjust") != "Yes")
		return OP_PASS
	shrinking = (A.step_value("mode") == "Shrink")
	size_limit = A.step_value("limit")
	return OP_PASS

/obj/structure/portal_event/resize/teleport(atom/movable/M as mob|obj)
	if(!isliving(M))
		return ..()
	var/mob/living/ourmob = M
	if(shrinking)
		if(ourmob.size_multiplier > size_limit)
			ourmob.resize(size_limit, FALSE, TRUE, TRUE)
	else
		if(ourmob.size_multiplier < size_limit)
			ourmob.resize(size_limit, FALSE, TRUE, TRUE)

	return ..()

/obj/structure/portal_event/resize/preset_shrink_twentyfive
	shrinking = TRUE
	size_limit = 0.25

/obj/structure/portal_event/resize/preset_shrink_fifty
	shrinking = TRUE
	size_limit = 0.5

/obj/structure/portal_event/resize/preset_shrink_hundred
	shrinking = TRUE
	size_limit = 1

/obj/structure/portal_event/resize/preset_grow_hundred
	shrinking = FALSE
	size_limit = 1

/obj/structure/portal_event/resize/preset_grow_twohundred
	shrinking = FALSE
	size_limit = 2

///// TIMER DOOR /////

/obj/structure/timer_door
	name = "door"
	desc = "It's a door with no apparent control mechanism! It opens on a timer!"
	icon = 'icons/obj/doors/Dooralien.dmi'
	icon_state = "door_locked"
	opacity = TRUE
	density = TRUE
	anchored = TRUE

	var/start_time
	var/time_til_open = 5 MINUTES

/obj/structure/timer_door/examine(mob/user, infix, suffix)
	. = ..()

	var/ourtime = (((start_time + time_til_open) - world.time) / 600)
	. += span_notice("It will open in [ourtime] minutes!")

/obj/structure/timer_door/Initialize(mapload)
	. = ..()
	EXPIRY_STAMP(src, start_time, CLOCK_WORLD)

CAPABILITIES(/obj/structure/timer_door)
	after_init(nameof(time_til_open), then(TYPE_PROC_REF(/datum, qdel_self)))

DESTROY_EFFECTS(/obj/structure/timer_door, new /datum/destroy_effects_data(message = "%SRC% opens up!", message_class = "danger", sound = SFX_EFFECTS_BANG, sound_volume = 75))

/obj/structure/timer_door/ten
	time_til_open = 10 MINUTES

/obj/structure/timer_door/fifteen
	time_til_open = 15 MINUTES

/obj/structure/timer_door/twenty
	time_til_open = 20 MINUTES
