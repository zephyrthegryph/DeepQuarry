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
		om_prompt_sequence(src, user, list(
			list("key" = "adjust", "message" = "Would you like to adjust the portal's size settings?", "title" = "Change portal size settings", "choices" = list("No","Yes")),
			PROC_REF(ask_size_mode),
			PROC_REF(ask_size_limit),
		), PROC_REF(size_settings_chosen), list("requires" = PROMPT_ADMIN(R_HOLDER)))
	return ..()

/obj/structure/portal_event/resize/proc/ask_size_mode(mob/user, datum/om/prompt/ask)
	if(ask.get("adjust") == "Yes")
		return list("key" = "mode", "message" = "Should this portal shrink people who are over the limit, or grow people who are under the limit?", "title" = "Change portal size settings", "choices" = list("Shrink","Grow"))

/obj/structure/portal_event/resize/proc/ask_size_limit(mob/user, datum/om/prompt/ask)
	switch(ask.get("mode"))
		if("Shrink")
			return list("key" = "limit", "kind" = "number", "message" = "What should the size limit be? Anyone over this limit will be shrunk to this size. (1 = 100%, etc)", "title" = "Pick a Size", "default" = 1, "round" = FALSE)
		if("Grow")
			return list("key" = "limit", "kind" = "number", "message" = "What should the size limit be? Anyone under this limit will be grown to this size. (1 = 100%, etc)", "title" = "Pick a Size", "default" = 1, "round" = FALSE)

/obj/structure/portal_event/resize/proc/size_settings_chosen(mob/user, datum/om/prompt/ask)
	if(isnull(ask.get("limit")))
		return
	shrinking = ask.get("mode") == "Shrink"
	size_limit = ask.get("limit")

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
	om_after(src, time_til_open, /datum/proc/qdel_self)

DESTROY_EFFECTS(/obj/structure/timer_door, new /datum/destroy_effects_data(message = "%SRC% opens up!", message_class = "danger", sound = 'sound/effects/bang.ogg', sound_volume = 75))

/obj/structure/timer_door/ten
	time_til_open = 10 MINUTES

/obj/structure/timer_door/fifteen
	time_til_open = 15 MINUTES

/obj/structure/timer_door/twenty
	time_til_open = 20 MINUTES
