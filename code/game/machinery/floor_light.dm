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

CAPABILITIES(/obj/item/floor_light)
	op("install", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(can_install_holds), because = PROC_REF(can_install_refusal))), then(PROC_REF(interaction_self)))

/// Installation must be able to consume the kit from its current holder.
/obj/item/floor_light/proc/can_install(mob/user, atom/target, obj/item/held)
	var/reason = loc?.release_refusal(src, user)
	if(reason)
		return reason
	return TRUE

/// Old attack_self.
/obj/item/floor_light/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!consume(src, user))
		return FALSE
	new /obj/machinery/floor_light(get_turf(user))
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

/obj/machinery/floor_light/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	set_anchored(!anchored)
	act_message(user, src, others = span_notice("%U% has [anchored ? "attached" : "detached"] %T%."))
	return OP_OK

/obj/machinery/floor_light/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!(damaged || (broken_now())))
		return OP_OK
	use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return OP_OK

/obj/machinery/floor_light/proc/welder_act_tool_done(mob/user)
	if(QDELETED(src))
		return ITEM_INTERACT_BLOCKING
	act_message(user, src, others = span_notice("%U% has repaired %T%."))
	atom_fix()
	damaged = null
	update_brightness()
	return ITEM_INTERACT_SUCCESS

MSG_DEF_SELF(floor_light/unanchored, "it must be screwed down first")

/// Requirement (was REQ_* can_switch): the legacy check answers TRUE to pass.
/obj/machinery/floor_light/proc/can_switch_holds(datum/act/op/A)
	var/answer = can_switch(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_switch_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/floor_light/proc/can_switch_refusal(datum/act/op/A)
	var/answer = can_switch(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/floor_light/proc/interaction_harm(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(held?.force)
		attack_hand(user)
	return OP_DECLINE

/obj/machinery/floor_light/proc/interaction_smash(datum/act/op/A)
	var/mob/user = A.actor
	if(issmall(user))
		return OP_DECLINE
	if(!isnull(damaged) && !broken_now())
		act_message(user, src, others = span_danger("%U% smashes %T%!"))
		play_sfx(src, SFX_SHATTER)
		atom_break()
	else
		act_message(user, src, others = span_danger("%U% attacks %T%!"))
		play_sfx(src, SFX_EFFECTS_GLASSHIT)
		if(isnull(damaged)) damaged = 0
	update_brightness()
	return OP_OK

/// Requirement: TRUE, or why the light can't be switched.
/obj/machinery/floor_light/proc/can_switch(mob/user, atom/target, obj/item/held)
	if(broken_now())
		return "it's too damaged to be functional"
	if(power_lost())
		return "it's unpowered"
	return TRUE

/obj/machinery/floor_light/proc/interaction_use(datum/act/op/A)
	set_on(!on)
	if(on) set_use_power(USE_POWER_ACTIVE)
	// visible_message(span_notice("\The [user] turns \the [src] [on ? "on" : "off"].")) // No thankouuuu. Too spammy.
	update_brightness()
	return OP_OK

/obj/machinery/floor_light/proc/work_step(datum/act/timer/A)
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

DECLARE_APPEARANCE_PROC(/obj/machinery/floor_light, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/floor_light/appearance_overlays()
	. = list()
	if(use_power && !broken())
		if(isnull(damaged))
			. += CACHED_KEY(floor_light_overlays, "floorlight-[default_light_colour]", "on", default_light_colour, layer+0.001)
		else
			if(damaged == 0) //Needs init.
				damaged = rand(1,4)
			. += CACHED_KEY(floor_light_overlays, "floorlight-broken[damaged]-[default_light_colour]", "flicker[damaged]", default_light_colour, layer+0.001)

/obj/machinery/floor_light/proc/broken()
	return (!operable())

CAPABILITIES(/obj/machinery/floor_light)
	started_work(step = PROC_REF(work_step))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(floor_light_blast))))
	op("use_welder", tool(TOOL_WELDER), priority(OP_PRIORITY_DEFAULT), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("floor_light_harm", item(/obj/item), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Hit"), passes(), then(PROC_REF(interaction_harm)))
	op("floor_light_smash", hand(), ungated(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Smash"), then(PROC_REF(interaction_smash)))
	op("floor_light_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), needs(req_is(nameof(anchored), TRUE, because = MSG(floor_light/unanchored)), req(PROC_REF(can_switch_holds), because = PROC_REF(can_switch_refusal))), then(PROC_REF(interaction_use)))

/// A lighter blast marks the light as (lightly) damaged.
/obj/machinery/floor_light/proc/floor_light_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(packet.severity >= 2 && isnull(damaged))
		damaged = 0
	return HOOK_DECLINE

/obj/machinery/floor_light/cultify()
	default_light_colour = "#FF0000"
	update_brightness()

/obj/item/floor_light/proc/can_install_holds(datum/act/op/A)
	return isturf(A.actor?.loc) && can_install(A.actor, src, A.held) == TRUE

/obj/item/floor_light/proc/can_install_refusal(datum/act/op/A)
	if(!isturf(A.actor?.loc))
		return "you can't use that here"
	var/result = can_install(A.actor, src, A.held)
	return istext(result) ? result : "the kit cannot be installed"
