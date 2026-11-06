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
	op("install", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(can_install))), then(PROC_REF(interaction_self)))

/// Installation must be able to consume the kit from its current holder.
/obj/item/floor_light/proc/can_install(datum/act/op/A)
	var/mob/user = A.actor
	if(!(user && (user in turf_contents_of_type(get_turf(user), /mob))))
		return "you can't use that here"
	// Sample the real custodian's policy; the atomic consume rechecks it too.
	var/obj/item/floor_light/kit = read_once(src)
	var/reason = read_once(kit.loc?.release_refusal(kit, user))
	if(reason)
		return reason
	return null

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

/// When the welder does nothing (the click is used up, nothing is said).
/obj/machinery/floor_light/proc/welder_refusal(datum/act/op/A)
	return read_once(!(damaged || (broken_now()))) ? "no" : null

/obj/machinery/floor_light/proc/welder_started(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 50, TRUE)

/obj/machinery/floor_light/proc/welder_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	if(QDELETED(src))
		return OP_OK
	act_message(user, src, others = span_notice("%U% has repaired %T%."))
	atom_fix()
	set_damaged(null)
	update_brightness()
	return OP_OK

MSG_DEF_SELF(floor_light/unanchored, "it must be screwed down first")

/obj/machinery/floor_light/proc/interaction_harm(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(combat_of(held).force)
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
		if(isnull(damaged))
			set_damaged(rand(1, 4))
	update_brightness()
	return OP_OK

/// Requirement: null, or why the light can't be switched.
/obj/machinery/floor_light/proc/can_switch(datum/act/op/A)
	if(broken_now())
		return "it's too damaged to be functional"
	if(power_lost())
		return "it's unpowered"
	return null

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

/// The light is lit while it is on and drawing its active power; else it stops drawing.
/obj/machinery/floor_light/proc/update_brightness()
	if(!lit())
		set_use_power(USE_POWER_OFF)
	update_active_power_usage(lit() ? (default_light_range + default_light_power) * 10 : 0)

/obj/machinery/floor_light/proc/lit()
	return on && use_power == USE_POWER_ACTIVE


/// What the panel shows while it draws power and works: its light, flickering once damaged, and the light it casts while lit.
/obj/machinery/floor_light/draw(datum/look/look)
	..()
	if(!use_power || broken())
		return
	if(isnull(damaged))
		look.overlay(CACHED_KEY(floor_light_overlays, "floorlight-[default_light_colour]", "on", default_light_colour, initial(layer)+0.001))
	else
		look.overlay(CACHED_KEY(floor_light_overlays, "floorlight-broken[damaged]-[default_light_colour]", "flicker[damaged]", default_light_colour, initial(layer)+0.001))
	if(lit())
		look.glow(GLOW(default_light_range, default_light_power, default_light_colour))

/obj/machinery/floor_light/proc/broken()
	return (!operable())

CAPABILITIES(/obj/machinery/floor_light)
	configure(uses_power(idle = 2, active = 20, channel = LIGHT))
	started_work(step = PROC_REF(work_step))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(floor_light_blast))))
	op("use_welder", lit_welder(fuel = 0), priority(OP_PRIORITY_DEFAULT), needs(req(PROC_REF(welder_refusal), silent = TRUE)), starts(PROC_REF(welder_started)), wait(2 SECONDS), then(PROC_REF(welder_act_tool_done)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("floor_light_harm", item(/obj/item), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Hit"), passes(), then(PROC_REF(interaction_harm)))
	op("floor_light_smash", hand(), ungated(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Smash"), then(PROC_REF(interaction_smash)))
	op("floor_light_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), needs(req_is(nameof(anchored), TRUE, because = MSG(floor_light/unanchored)), req(PROC_REF(can_switch))), then(PROC_REF(interaction_use)))

/// A lighter blast marks the light as (lightly) damaged.
/obj/machinery/floor_light/proc/floor_light_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(packet.severity >= 2 && isnull(damaged))
		set_damaged(rand(1, 4))
	return HOOK_DECLINE

/obj/machinery/floor_light/cultify()
	set_default_light_colour("#FF0000")
	update_brightness()
