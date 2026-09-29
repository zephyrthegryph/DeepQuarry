/obj/structure/portal_event/resize
	name = "portal"
	desc = "It leads to someplace else!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "type-d-portal"
	var/shrinking = TRUE
	var/size_limit = 0.5

/// Old attack_ghost: staff also get the size settings, then the portal's own ghost use.
/obj/structure/portal_event/resize/portal_event_ghost_use(mob/observer/dead/user, obj/item/held, datum/interaction/interaction)
	if(!target && check_rights_for(user?.client, R_HOLDER))
		om_ask(user, /datum/om/prompt/confirm, PROC_REF(ask_size_mode), title = "Change portal size settings", message = "Would you like to adjust the portal's size settings?", no_first = TRUE, requires = PROMPT_ADMIN(R_HOLDER))
	return ..()

/datum/om/prompt/number/portal_size_limit
	title = "Pick a Size"
	default = 1
	round_entry = FALSE
	requires = PROMPT_ADMIN(R_HOLDER)
	var/shrinking = TRUE

/datum/om/prompt/number/portal_size_limit/prepare()
	message = shrinking ? "What should the size limit be? Anyone over this limit will be shrunk to this size. (1 = 100%, etc)" : "What should the size limit be? Anyone under this limit will be grown to this size. (1 = 100%, etc)"
	return TRUE

/obj/structure/portal_event/resize/proc/ask_size_mode(datum/om/prompt/confirm/ask)
	om_ask(ask.answerer, /datum/om/prompt/choice, PROC_REF(ask_size_limit), title = "Change portal size settings", message = "Should this portal shrink people who are over the limit, or grow people who are under the limit?", choices = list("Shrink","Grow"), buttons = TRUE, requires = PROMPT_ADMIN(R_HOLDER))

/obj/structure/portal_event/resize/proc/ask_size_limit(datum/om/prompt/choice/ask)
	om_ask(ask.answerer, /datum/om/prompt/number/portal_size_limit, PROC_REF(size_settings_chosen), shrinking = (ask.choice == "Shrink"))

/obj/structure/portal_event/resize/proc/size_settings_chosen(datum/om/prompt/number/portal_size_limit/ask)
	if(isnull(ask.number))
		return
	shrinking = ask.shrinking
	size_limit = ask.number

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
	start_time = world.time

DECLARE_START_TIMER(/obj/structure/timer_door, "time_til_open", /datum/proc/qdel_self)

DESTROY_EFFECTS(/obj/structure/timer_door, new /datum/destroy_effects_data(message = "%SRC% opens up!", message_class = "danger", sound = SFX_EFFECTS_BANG, sound_volume = 75))

/obj/structure/timer_door/ten
	time_til_open = 10 MINUTES

/obj/structure/timer_door/fifteen
	time_til_open = 15 MINUTES

/obj/structure/timer_door/twenty
	time_til_open = 20 MINUTES
