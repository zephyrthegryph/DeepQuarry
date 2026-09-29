DECLARE_SHARED_CACHE(floor_light_overlays, GLOBAL_PROC_REF(build_floor_light_overlay), SC_NEVER)

/// Builder for floor_light_overlays.
/proc/build_floor_light_overlay(state, colour, layer)
	var/image/I = image(state)
	I.color = colour
	I.layer = layer
	return I

MATERIAL_MIX(/obj/item/floor_light, list(MAT_STEEL = 2500, MAT_GLASS = 2750))
/obj/item/floor_light
	name = "floor light kit"
	desc = "A backlit floor panel, ready for installation!"
	icon = 'icons/obj/machines/floor_light.dmi'
	icon_state = "item"

DECLARE_INTERACTIONS(/obj/item/floor_light, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/floor_light/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/turf/T = get_turf(user)
	if(!T)
		to_chat(user, span_warning("You need to be on a floor to install this."))
		return TRUE
	new /obj/machinery/floor_light(T)
	qdel(src)
	return TRUE

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

	on = null
	var/damaged
	var/default_light_range = 4
	var/default_light_power = 0.75
	var/default_light_colour = LIGHT_COLOR_INCANDESCENT_BULB

/obj/machinery/floor_light/prebuilt
	anchored = TRUE

/obj/machinery/floor_light/screwdriver_act(mob/user, obj/item/tool)
	set_anchored(!anchored)
	act_message(user, src, others = span_notice("%U% has [anchored ? "attached" : "detached"] %T%."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floor_light/welder_act(mob/user, obj/item/tool)
	if(!(damaged || (has_stat(BROKEN))))
		return ITEM_INTERACT_BLOCKING
	use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floor_light/proc/welder_act_tool_done(mob/user)
	if(QDELETED(src))
		return ITEM_INTERACT_BLOCKING
	act_message(user, src, others = span_notice("%U% has repaired %T%."))
	atom_fix()
	damaged = null
	update_brightness()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floor_light/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/floor_light_harm,
		/datum/interaction/machine_hand/ungated/floor_light_smash,
		/datum/interaction/machine_hand/ungated/floor_light_use,
	)
	..()

/// The old attackby: if a harmful item is used in combat mode, run the attack_hand
/// smash behavior, but always fall through to the base attack chain (it never stopped it).
/datum/interaction/machine_item/floor_light_harm
	id = "floor_light_harm"
	name = "Hit"
	stance = I_HURT
	consumes_input = FALSE
	effect = /obj/machinery/floor_light/proc/interaction_harm

/obj/machinery/floor_light/proc/interaction_harm(mob/user, obj/item/held, datum/interaction/interaction)
	if(held?.force)
		attack_hand(user)
	return FALSE

/// Combat mode: smash the light (small mobs can't, and just use it).
/datum/interaction/machine_hand/ungated/floor_light_smash
	id = "floor_light_smash"
	name = "Smash"
	stance = I_HURT
	effect = /obj/machinery/floor_light/proc/interaction_smash

/obj/machinery/floor_light/proc/interaction_smash(mob/user, obj/item/held, datum/interaction/interaction)
	if(issmall(user))
		return FALSE
	if(!isnull(damaged) && !has_stat(BROKEN))
		act_message(user, src, others = span_danger("%U% smashes %T%!"))
		play_sfx(src, SFX_SHATTER)
		atom_break()
	else
		act_message(user, src, others = span_danger("%U% attacks %T%!"))
		play_sfx(src, SFX_EFFECTS_GLASSHIT)
		if(isnull(damaged)) damaged = 0
	update_brightness()
	return TRUE

/datum/interaction/machine_hand/ungated/floor_light_use
	id = "floor_light_use"
	name = "Use"
	effect = /obj/machinery/floor_light/proc/interaction_use

/obj/machinery/floor_light/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!anchored)
		to_chat(user, span_warning("\The [src] must be screwed down first."))
		return TRUE

	if(has_stat(BROKEN))
		to_chat(user, span_warning("\The [src] is too damaged to be functional."))
		return TRUE

	if(has_stat(NOPOWER))
		to_chat(user, span_warning("\The [src] is unpowered."))
		return TRUE

	set_on(!on)
	if(on) set_use_power(USE_POWER_ACTIVE)
	// visible_message(span_notice("\The [user] turns \the [src] [on ? "on" : "off"].")) // No thankouuuu. Too spammy.
	update_brightness()
	return TRUE

/obj/machinery/floor_light/machine_step()
	..()
	var/need_update
	if((!anchored || broken()) && on)
		set_use_power(USE_POWER_OFF)
		set_on(0)
		need_update = 1
	else if(use_power && !on)
		set_use_power(USE_POWER_OFF)
		need_update = 1
	if(need_update)
		update_brightness()
	return PROCESS_KILL

/obj/machinery/floor_light/proc/update_brightness()
	if(on && use_power == USE_POWER_ACTIVE)
		if(light_range != default_light_range || light_power != default_light_power || light_color != default_light_colour)
			set_light(default_light_range, default_light_power, default_light_colour)
	else
		set_use_power(USE_POWER_OFF)
		if(light_range || light_power)
			set_light(0)

	update_active_power_usage((light_range + light_power) * 10)
	update_icon()

/obj/machinery/floor_light/update_icon()
	cut_overlays()
	if(use_power && !broken())
		if(isnull(damaged))
			add_overlay(CACHED_KEY(floor_light_overlays, "floorlight-[default_light_colour]", "on", default_light_colour, layer+0.001))
		else
			if(damaged == 0) //Needs init.
				damaged = rand(1,4)
			add_overlay(CACHED_KEY(floor_light_overlays, "floorlight-broken[damaged]-[default_light_colour]", "flicker[damaged]", default_light_colour, layer+0.001))

/obj/machinery/floor_light/proc/broken()
	return (!operable())

/obj/machinery/floor_light/ex_act(severity)
	if(severity >= 2 && isnull(damaged))
		damaged = 0
	return ..()

/obj/machinery/floor_light/cultify()
	default_light_colour = "#FF0000"
	update_brightness()
