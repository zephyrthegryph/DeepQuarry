/obj/structure/portal_event/resize
	name = "portal"
	desc = "It leads to someplace else!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "type-d-portal"
	var/shrinking = TRUE
	var/size_limit = 0.5

/// Old attack_ghost: staff also get the size settings, then the portal's own ghost use.
/obj/structure/portal_event/resize/portal_event_ghost_use(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	if(!target && check_rights_for(user?.client, R_HOLDER))
		open_request(src, /datum/prompt/choice, PROC_REF(ask_size_mode), answerer = user, title = "Change portal size settings", question = "Would you like to adjust the portal's size settings?", choices = list("No", "Yes"), buttons = TRUE, rights = R_HOLDER, timeout = 0)
	return ..()

/datum/prompt/number/portal_size_limit
	title = "Pick a Size"
	default = 1
	step = null
	min_value = 0
	max_value = INFINITY
	timeout = 0
	rights = R_HOLDER
	var/shrinking = TRUE

/datum/prompt/number/portal_size_limit/prepare(datum/act/A)
	. = ..()
	question = shrinking ? "What should the size limit be? Anyone over this limit will be shrunk to this size. (1 = 100%, etc)" : "What should the size limit be? Anyone under this limit will be grown to this size. (1 = 100%, etc)"

/datum/prompt/number/portal_size_limit/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, max_value, min_value, timeout, FALSE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/obj/structure/portal_event/resize/proc/ask_size_mode(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	return open_size_mode(A.request.answerer)

/obj/structure/portal_event/resize/proc/open_size_mode(mob/user)
	open_request(src, /datum/prompt/choice, PROC_REF(ask_size_limit), answerer = user, title = "Change portal size settings", question = "Should this portal shrink people who are over the limit, or grow people who are under the limit?", choices = list("Shrink","Grow"), buttons = TRUE, rights = R_HOLDER, timeout = 0)

/obj/structure/portal_event/resize/proc/ask_size_limit(datum/act/request/A)
	if(!A.answer)
		return
	open_request(src, /datum/prompt/number/portal_size_limit, PROC_REF(size_settings_chosen), answerer = A.request.answerer, shrinking = (A.answer.value == "Shrink"))

/obj/structure/portal_event/resize/proc/size_settings_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return apply_size_settings(A)

/obj/structure/portal_event/resize/proc/apply_size_settings(datum/act/request/A)
	var/datum/prompt/number/portal_size_limit/ask = A.request
	shrinking = ask.shrinking
	size_limit = A.answer.value

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
