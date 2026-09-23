GLOBAL_LIST_EMPTY(floor_light_cache)

/obj/item/floor_light
	name = "floor light kit"
	desc = "A backlit floor panel, ready for installation!"
	icon = 'icons/obj/machines/floor_light.dmi'
	icon_state = "item"
	MATERIAL_MIX(list(MAT_STEEL = 2500, MAT_GLASS = 2750))

/obj/item/floor_light/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/turf/T = get_turf(user)
	if(!T)
		to_chat(user, span_warning("You need to be on a floor to install this."))
		return
	new /obj/machinery/floor_light(T)
	qdel(src)

/obj/machinery/floor_light
	name = "floor light"
	icon = 'icons/obj/machines/floor_light.dmi'
	icon_state = "base"
	desc = "A backlit floor panel."
	layer = TURF_LAYER+0.001
	anchored = FALSE
	use_power = USE_POWER_ACTIVE
	idle_power_usage = 2
	active_power_usage = 20
	power_channel = LIGHT

	var/on
	var/damaged
	var/default_light_range = 4
	var/default_light_power = 0.75
	var/default_light_colour = LIGHT_COLOR_INCANDESCENT_BULB

/obj/machinery/floor_light/prebuilt
	anchored = TRUE

/obj/machinery/floor_light/screwdriver_act(mob/user, obj/item/tool)
	anchored = !anchored
	visible_message(span_notice("\The [user] has [anchored ? "attached" : "detached"] \the [src]."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floor_light/welder_act(mob/user, obj/item/tool)
	if(!(damaged || (stat & BROKEN)))
		return ITEM_INTERACT_BLOCKING
	if(!use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50))
		return ITEM_INTERACT_BLOCKING
	if(QDELETED(src))
		return ITEM_INTERACT_BLOCKING
	visible_message(span_notice("\The [user] has repaired \the [src]."))
	atom_fix()
	damaged = null
	update_brightness()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floor_light/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/floor_light_harm,
		/datum/interaction/machine_hand/ungated/floor_light_use,
	)
	..()

/// The old attackby: if a harmful item is used in combat mode, run the attack_hand
/// smash behavior, but always fall through to the base attack chain (it never stopped it).
/datum/interaction/machine_item/floor_light_harm
	id = "floor_light_harm"
	name = "Hit"
	offered_when = list(REQ_COMBAT_MODE)
	tags = list(INTERACTION_TAG_HOSTILE)
	consumes_input = FALSE
	effect = /obj/machinery/floor_light/proc/interaction_harm

/obj/machinery/floor_light/proc/interaction_harm(mob/user, obj/item/held, datum/interaction/interaction)
	if(held?.force)
		attack_hand(user)
	return FALSE

/datum/interaction/machine_hand/ungated/floor_light_use
	id = "floor_light_use"
	name = "Use"
	effect = /obj/machinery/floor_light/proc/interaction_use

/obj/machinery/floor_light/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(IS_HARMING(user) && !issmall(user))
		if(!isnull(damaged) && !(stat & BROKEN))
			visible_message(span_danger("\The [user] smashes \the [src]!"))
			playsound(src, "shatter", 70, 1)
			atom_break()
		else
			visible_message(span_danger("\The [user] attacks \the [src]!"))
			playsound(src, 'sound/effects/Glasshit.ogg', 75, 1)
			if(isnull(damaged)) damaged = 0
		update_brightness()
		return TRUE
	else

		if(!anchored)
			to_chat(user, span_warning("\The [src] must be screwed down first."))
			return TRUE

		if(stat & BROKEN)
			to_chat(user, span_warning("\The [src] is too damaged to be functional."))
			return TRUE

		if(stat & NOPOWER)
			to_chat(user, span_warning("\The [src] is unpowered."))
			return TRUE

		on = !on
		if(on) update_use_power(USE_POWER_ACTIVE)
		// visible_message(span_notice("\The [user] turns \the [src] [on ? "on" : "off"].")) // No thankouuuu. Too spammy.
		update_brightness()
		return TRUE

/obj/machinery/floor_light/process()
	..()
	var/need_update
	if((!anchored || broken()) && on)
		update_use_power(USE_POWER_OFF)
		on = 0
		need_update = 1
	else if(use_power && !on)
		update_use_power(USE_POWER_OFF)
		need_update = 1
	if(need_update)
		update_brightness()
	return PROCESS_KILL

/obj/machinery/floor_light/proc/update_brightness()
	if(on && use_power == USE_POWER_ACTIVE)
		if(light_range != default_light_range || light_power != default_light_power || light_color != default_light_colour)
			set_light(default_light_range, default_light_power, default_light_colour)
	else
		update_use_power(USE_POWER_OFF)
		if(light_range || light_power)
			set_light(0)

	update_active_power_usage((light_range + light_power) * 10)
	update_icon()

/obj/machinery/floor_light/update_icon()
	cut_overlays()
	if(use_power && !broken())
		if(isnull(damaged))
			var/cache_key = "floorlight-[default_light_colour]"
			if(!GLOB.floor_light_cache[cache_key])
				var/image/I = image("on")
				I.color = default_light_colour
				I.layer = layer+0.001
				GLOB.floor_light_cache[cache_key] = I
			add_overlay(GLOB.floor_light_cache[cache_key])
		else
			if(damaged == 0) //Needs init.
				damaged = rand(1,4)
			var/cache_key = "floorlight-broken[damaged]-[default_light_colour]"
			if(!GLOB.floor_light_cache[cache_key])
				var/image/I = image("flicker[damaged]")
				I.color = default_light_colour
				I.layer = layer+0.001
				GLOB.floor_light_cache[cache_key] = I
			add_overlay(GLOB.floor_light_cache[cache_key])

/obj/machinery/floor_light/proc/broken()
	return (stat & (BROKEN|NOPOWER))

/obj/machinery/floor_light/ex_act(severity)
	if(severity >= 2 && isnull(damaged))
		damaged = 0
	return ..()

/obj/machinery/floor_light/Destroy()
	var/area/A = get_area(src)
	if(A)
		on = 0
	. = ..()

/obj/machinery/floor_light/cultify()
	default_light_colour = "#FF0000"
	update_brightness()
