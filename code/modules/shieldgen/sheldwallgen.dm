////FIELD GEN START //shameless copypasta from fieldgen, powersink, and grille
/obj/machinery/shieldwallgen
		name = "shield generator"
		desc = "A shield generator."
		icon = 'icons/obj/stationobjs.dmi'
		icon_state = "Shield_Gen"
		anchored = FALSE
		density = TRUE
		req_access = list(ACCESS_ENGINE_EQUIP)
		active = 0
		var/power = 0
		state = 0
		var/steps = 0
		var/last_check = 0
		var/check_delay = 10
		var/recalc = 0
		locked = 1
		var/destroyed = 0
		var/directwired = 1
		var/obj/structure/cable/attached		// the attached cable
		var/storedpower = 0
		//There have to be at least two posts, so these are effectively doubled
		var/power_draw = 30000 //30 kW. How much power is drawn from powernet. Increase this to allow the generator to sustain longer shields, at the cost of more power draw.
		var/max_stored_power = 50000 //50 kW
		use_power = USE_POWER_OFF	//Draws directly from power net. Does not use APC power.

/// Runs while switched on, or while bolted down to charge its store (it parks once full).
OM_DERIVE_FIELD(/obj/machinery/shieldwallgen, wallgen_has_work, list("active", "anchored"))
/obj/machinery/shieldwallgen/proc/wallgen_has_work()
	return active || anchored
CAPABILITIES(/obj/machinery/shieldwallgen)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(wallgen_has_work), wakes_on = list(nameof(active), nameof(anchored)))
	climb()

/obj/machinery/shieldwallgen/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/shieldwallgen_id_swipe,
		/datum/interaction/machine_item/shieldwallgen_hit,
		/datum/interaction/machine_hand/ungated/shieldwallgen_toggle,
	)
	..()

/// Old attack_hand: never called ..(), so ungated.
/datum/interaction/machine_hand/ungated/shieldwallgen_toggle
	id = "shieldwallgen_toggle"
	name = "Toggle"
	effect = /obj/machinery/shieldwallgen/proc/interaction_toggle
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/shieldwallgen/proc/can_toggle))

/// Requirement: TRUE, or why the generator can't be switched.
/obj/machinery/shieldwallgen/proc/can_toggle(mob/user, atom/target, obj/item/held)
	if(state != 1)
		return "the shield generator needs to be firmly secured to the floor first"
	if(locked && !issilicon(user))
		return "the controls are locked"
	if(power != 1)
		return "the shield generator needs to be powered by wire underneath"
	return TRUE

/obj/machinery/shieldwallgen/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)

	if(src.active >= 1)
		set_active(0)
		icon_state = "Shield_Gen"

		act_message(user, null, MSG_SELF("You turn off the shield generator."), \
			MSG_OTHERS("%U% turned the shield generator off."), \
			MSG_BLIND("You hear heavy droning fade out."))
		for(var/dir in list(1,2,4,8)) src.cleanup(dir)
	else
		set_active(1)
		icon_state = "Shield_Gen_on"
		act_message(user, null, MSG_SELF("You turn on the shield generator."), \
			MSG_OTHERS("%U% turned the shield generator on."), \
			MSG_BLIND("You hear heavy droning."))
	src.add_fingerprint(user)
	return TRUE

/obj/machinery/shieldwallgen/proc/power()
	if(!anchored)
		power = 0
		return 0
	var/turf/T = src.loc

	var/obj/structure/cable/C = T.get_cable_node()
	var/PN = 0
	if(C)	PN = C.get_power_region()		// the power region of the connected cable

	if(!PN)
		power = 0
		return 0

	var/shieldload = between(500, max_stored_power - storedpower, power_draw)	//what we try to draw
	shieldload = power_draw(PN, shieldload) //what we actually get
	storedpower += shieldload

	//If we're still in the red, then there must not be enough available power to cover our load.
	if(storedpower <= 0)
		power = 0
		return 0

	power = 1	// IVE GOT THE POWER!
	return 1

/obj/machinery/shieldwallgen/proc/work_step(datum/act/timer/A)
	if(!active && storedpower >= max_stored_power)
		storedpower = max_stored_power
		return PROCESS_KILL // charged: parks until switched on (or re-bolted)
	power()
	if(power && active)
		storedpower -= 2500 //the generator post itself uses some power

	if(storedpower >= max_stored_power)
		storedpower = max_stored_power
	if(storedpower <= 0)
		storedpower = 0

	if(src.active == 1)
		if(!src.state == 1)
			set_active(0)
			return
		after(src, 0.1 SECONDS, PROC_REF(setup_field), with = list(1))
		after(src, 0.2 SECONDS, PROC_REF(setup_field), with = list(2))
		after(src, 0.3 SECONDS, PROC_REF(setup_field), with = list(4))
		after(src, 0.4 SECONDS, PROC_REF(setup_field), with = list(8))
		set_active(2)
	if(src.active >= 1)
		if(src.power == 0)
			src.visible_message(span_red("The [src.name] shuts down due to lack of power!"), \
				"You hear heavy droning fade out")
			icon_state = "Shield_Gen"
			set_active(0)
			for(var/dir in list(1,2,4,8)) src.cleanup(dir)
	if(!active && storedpower >= max_stored_power)
		return PROCESS_KILL

/obj/machinery/shieldwallgen/proc/setup_field(NSEW = 0)
	var/turf/T = src.loc
	var/turf/T2 = src.loc
	var/obj/machinery/shieldwallgen/G
	var/steps = 0
	var/oNSEW = 0

	if(!NSEW)//Make sure its ran right
		return

	if(NSEW == 1)
		oNSEW = 2
	else if(NSEW == 2)
		oNSEW = 1
	else if(NSEW == 4)
		oNSEW = 8
	else if(NSEW == 8)
		oNSEW = 4

	for(var/dist = 0, dist <= 9, dist += 1) // checks out to 8 tiles away for another generator
		T = get_step(T2, NSEW)
		T2 = T
		steps += 1
		if(locate_on(T, /obj/machinery/shieldwallgen))
			G = (locate_on(T, /obj/machinery/shieldwallgen))
			steps -= 1
			if(!G.active)
				return
			G.cleanup(oNSEW)
			break

	if(isnull(G))
		return

	T2 = src.loc

	for(var/dist = 0, dist < steps, dist += 1) // creates each field tile
		var/field_dir = get_dir(T2,get_step(T2, NSEW))
		T = get_step(T2, NSEW)
		T2 = T
		var/obj/machinery/shieldwall/CF = new/obj/machinery/shieldwall(T, src, G) //(ref to this gen, ref to connected gen)
		CF.set_dir(field_dir)

/// Old attackby: never called ..(), so both branches stay in their effects.
/datum/interaction/machine_item/shieldwallgen_id_swipe
	id = "shieldwallgen_id_swipe"
	name = "Swipe ID"
	held_type = list(/obj/item/card/id, /obj/item/pda)
	effect = /obj/machinery/shieldwallgen/proc/interaction_id_swipe

/obj/machinery/shieldwallgen/proc/interaction_id_swipe(mob/user, obj/item/W, datum/interaction/interaction)
	if (src.allowed(user))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
	else
		to_chat(user, span_red("Access denied."))
	return TRUE

/datum/interaction/machine_item/shieldwallgen_hit
	id = "shieldwallgen_hit"
	name = "Hit"
	held_type = /obj/item
	effect = /obj/machinery/shieldwallgen/proc/interaction_hit

/obj/machinery/shieldwallgen/proc/interaction_hit(mob/user, obj/item/W, datum/interaction/interaction)
	src.add_fingerprint(user)
	act_message(src, user, others = span_red("%U% has been hit with %I% by %T%!"), item = W)
	return TRUE

/obj/machinery/shieldwallgen/wrench_act(mob/user, obj/item/W)
	if(active)
		to_chat(user, "Turn off the field generator first.")
		return ITEM_INTERACT_BLOCKING
	set_state(!state)
	set_anchored(state)
	playsound(src, W.usesound, 75, 1)
	to_chat(user, "You [anchored ? "secure" : "undo"] the external reinforcing bolts[anchored ? " to" : " from"] the floor.")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/shieldwallgen/proc/cleanup(NSEW)
	var/obj/machinery/shieldwall/F
	var/obj/machinery/shieldwallgen/G
	var/turf/T = src.loc
	var/turf/T2 = src.loc

	for(var/dist = 0, dist <= 9, dist += 1) // checks out to 8 tiles away for fields
		T = get_step(T2, NSEW)
		T2 = T
		if(locate_on(T, /obj/machinery/shieldwall))
			F = (locate_on(T, /obj/machinery/shieldwall))
			spent(F)

		if(locate_on(T, /obj/machinery/shieldwallgen))
			G = (locate_on(T, /obj/machinery/shieldwallgen))
			if(!G.active)
				break

// its walls come down in every direction.
/obj/machinery/shieldwallgen/on_destroy(force)
	src.cleanup(1)
	src.cleanup(2)
	src.cleanup(4)
	src.cleanup(8)
	..()

/obj/machinery/shieldwallgen/bullet_act(obj/item/projectile/Proj)
	storedpower -= 400 * Proj.get_structure_damage()
	..()
	return

//////////////Containment Field START
/obj/machinery/shieldwall
		name = "Shield"
		desc = "An energy shield."
		icon = 'icons/effects/effects.dmi'
		icon_state = "shieldwall"
		anchored = TRUE
		density = TRUE
		unacidable = TRUE
		light_range = 3
		var/needs_power = 0
		active = 1
		var/delay = 5
		var/last_active
		var/mob/U
		var/obj/machinery/shieldwallgen/gen_primary
		var/obj/machinery/shieldwallgen/gen_secondary
		var/power_usage = 2500	//how much power it takes to sustain the shield
		var/generate_power_usage = 7500	//how much power it takes to start up the shield

CAPABILITIES(/obj/machinery/shieldwall)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	param(nameof(gen_primary), pos = 1)
	param(nameof(gen_secondary), pos = 2, apply = PROC_REF(span_generators))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A wall stands between two active generators, which pay for it.
/obj/machinery/shieldwall/proc/span_generators(obj/machinery/shieldwallgen/B)
	update_nearby_tiles()
	var/obj/machinery/shieldwallgen/A = gen_primary
	if(istype(A) && istype(B) && A.active && B.active)
		needs_power = 1
		if(prob(50))
			A.storedpower -= generate_power_usage
		else
			B.storedpower -= generate_power_usage
	else
		spent(src)

/obj/machinery/shieldwall/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/shieldwall_touch_block,
	)
	..()

/// Old attack_hand did nothing at all and never called ..(); ungated so no gate side effects sneak in.
/datum/interaction/machine_hand/ungated/shieldwall_touch_block
	id = "shieldwall_touch_block"
	name = "Touch"
	effect = /atom/proc/interaction_swallow

/obj/machinery/shieldwall/proc/work_step(datum/act/timer/A)
	if(needs_power)
		if(isnull(gen_primary)||isnull(gen_secondary))
			spent(src)
			return

		if(!(gen_primary.active)||!(gen_secondary.active))
			spent(src)
			return

		if(prob(50))
			gen_primary.storedpower -= power_usage
		else
			gen_secondary.storedpower -= power_usage

/obj/machinery/shieldwall/bullet_act(obj/item/projectile/Proj)
	if(needs_power)
		var/obj/machinery/shieldwallgen/G
		if(prob(50))
			G = gen_primary
		else
			G = gen_secondary
		G.storedpower -= 400 * Proj.get_structure_damage()
	..()
	return

DAMAGE_REACTION(/obj/machinery/shieldwall, DAMAGE_EXPLOSION, PROC_REF(shieldwall_blast_drain))

/// The wall itself is energy; the blast drains a generator instead.
/obj/machinery/shieldwall/proc/shieldwall_blast_drain(datum/damage_packet/packet)
	if(needs_power)
		var/obj/machinery/shieldwallgen/G = prob(50) ? gen_primary : gen_secondary
		var/static/list/drain = list(120000, 30000, 12000)
		G.storedpower -= drain[clamp(round(packet.severity), 1, 3)]
	return DAMAGE_REACTION_BLOCK

/obj/machinery/shieldwall/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return prob(20)
	if(istype(mover, /obj/item/projectile))
		return prob(10)
	return !density

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/shieldwall/step_start_condition()
	return needs_power
