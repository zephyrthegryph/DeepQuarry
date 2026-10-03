// The legacy touch, strike, plasteel, repair and emag of a door, kept for the door types that still carry their own (airlock, firedoor, blast door,
// windoor, unpowered): they set legacy_door_ops and drop the new door ops with legacy_door_ops(). The plain door (door.dm) declares all of these as ops.
// Each type that converts deletes its set_ line; this file goes when the last one has (steps 2 and 3 of the doors conversion).

/// The new door ops (code/library/machine/doors.dm, the base door's own ops) a legacy door type does not have: it answers these with the procs below.
/proc/legacy_door_ops()
	return list(without(CAP_DOORS), without(CAP_EMAG), without("strike"), without("reinforce"), without("weld_plasteel"), without("unreinforce"), without("repair"))

CAPABILITIES(/obj/machinery/door/airlock, legacy_door_ops())
CAPABILITIES(/obj/machinery/door/firedoor, legacy_door_ops())
CAPABILITIES(/obj/machinery/door/blast, legacy_door_ops())
CAPABILITIES(/obj/machinery/door/window, legacy_door_ops())
CAPABILITIES(/obj/machinery/door/unpowered, legacy_door_ops())

/obj/machinery/door/declare_interactions(list/into)
	if(!legacy_door_ops)
		return ..()
	into += list(
		/datum/interaction/machine_item/door_strike,
		/datum/interaction/machine_item/door_use_item,
		/datum/interaction/machine_hand/door_use,
	)
	into += dq_interaction_from_spec(type, INTERACT_TK(null, PROC_REF(interaction_door_tk)))
	..()

/datum/interaction/machine_hand/door_use
	id = "door_use"
	name = "Use"
	effect = /obj/machinery/door/proc/interaction_door_use

/obj/machinery/door/proc/interaction_door_use(mob/user, obj/item/held, datum/interaction/interaction)
	try_to_activate_door(user)
	return TRUE

/// Old attack_tk: an ID-locked door ignores telekinesis; otherwise the default telekinetic poke.
/obj/machinery/door/proc/interaction_door_tk(mob/user, obj/item/held, datum/interaction/interaction)
	return requiresID() && !allowed(null)

/// Combat mode: strike the closed door with the held item (plasteel still reinforces and cards still open it).
/datum/interaction/machine_item/door_strike
	id = "door_strike"
	name = "Strike"
	stance = I_HURT
	effect = /obj/machinery/door/proc/interaction_door_strike

/obj/machinery/door/proc/interaction_door_strike(mob/user, obj/item/W, datum/interaction/interaction)
	//psa to whoever coded this, there are plenty of objects that need to call attack() on doors without bludgeoning them.
	if(!density || !istype(W) || istype(W, /obj/item/card))
		return FALSE
	if(istype(W, /obj/item/stack/material) && W.get_material_name() == MAT_PLASTEEL)
		return FALSE
	add_fingerprint(user)
	user.setClickCooldown(user.get_attack_speed(W))
	if(W.obj_damage_type())
		user.do_attack_animation(src)
		if(W.force < min_force)
			act_message(user, src, others = span_danger("%U% hits %T% with %I% with no visible effect."), item = W)
		else
			act_message(user, src, others = span_danger("%U% forcefully strikes %T% with %I%!"), item = W)
			playsound(src, hitsound, 100, 1)
			receive_weapon_hit(W, user, silent = FALSE)
	return TRUE

/datum/interaction/machine_item/door_use_item
	id = "door_use_item"
	name = "Use"
	effect = /obj/machinery/door/proc/interaction_door_use_item

// NOTE (approximation): the old attackby had a mid-body `if(..()) return` after the
// plasteel-reinforce branch, gating the weapon-hit branch and try_to_activate_door() on
// whether the base atom's attackby signal chain intercepted the item. There's no direct way
// to invoke just that signal check from an interaction effect, so this always falls through
// past it (as if the signal never intercepted). Flagged for the lead: if any component hooks
// the attackby signal to intercept items on doors (e.g. a reagent sprayer), this loses that
// early-return and always proceeds to the weapon-hit / activate-door logic instead.
/obj/machinery/door/proc/interaction_door_use_item(mob/user, obj/item/I, datum/interaction/interaction)
	add_fingerprint(user)

	if(istype(I, /obj/item/stack/material) && I.get_material_name() == MAT_PLASTEEL)
		if(heat_proof)
			to_chat(user, span_warning("\The [src] is already reinforced."))
			return TRUE
		if((has_stat(BROKEN)) || (get_integrity() < max_integrity))
			to_chat(user, span_notice("It looks like \the [src] broken. Repair it before reinforcing it."))
			return TRUE
		if(!density)
			to_chat(user, span_warning("\The [src] must be closed before you can reinforce it."))
			return TRUE

		var/amount_needed = 2

		var/obj/item/stack/stack = I
		var/amount_given = amount_needed - reinforcing
		var/mats_given = stack.get_amount()
		var/singular_name = stack.singular_name
		if(reinforcing && amount_given <= 0)
			to_chat(user, span_warning("You must weld or remove \the plasteel from \the [src] before you can add anything else."))
		else
			if(mats_given >= amount_given)
				if(stack.use(amount_given))
					set_reinforcing(reinforcing + amount_given)
			else
				if(stack.use(mats_given))
					set_reinforcing(reinforcing + mats_given)
					amount_given = mats_given
		if(amount_given)
			to_chat(user, span_notice("You fit [amount_given] [singular_name]\s on \the [src]."))
		return TRUE

	try_to_activate_door(user)
	return TRUE

/obj/machinery/door/crowbar_act(mob/user, obj/item/tool)
	if(!legacy_door_ops || !reinforcing)
		return ..() // the door's crowbar interactions (an airlock's cap_pry())
	var/obj/item/stack/material/plasteel/reinforcing_sheet = new /obj/item/stack/material/plasteel(get_turf(src), reinforcing)
	set_reinforcing(0)
	to_chat(user, span_notice("You remove \the [reinforcing_sheet]."))
	playsound(src, tool.usesound, 100, 1)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/door/welder_act(mob/user, obj/item/tool)
	if(!legacy_door_ops)
		return ..()
	if(reinforcing)
		if(!density)
			to_chat(user, span_warning("\The [src] must be closed before you can reinforce it."))
			return ITEM_INTERACT_BLOCKING

		if(reinforcing < 2)
			to_chat(user, span_warning("You will need more plasteel to reinforce \the [src]."))
			return ITEM_INTERACT_BLOCKING

		use_tool(user, tool, src, delay = 1 SECOND, quality = TOOL_WELDER, volume = 50, amount = 0, start_self = "You start welding the plasteel into place.", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
		return ITEM_INTERACT_SUCCESS

	// The door's welder interactions first (an airlock's cap_weld_shut(), offered only where welding it
	// shut wins over repairing it), then the repair.
	. = ..()
	if(.)
		return

	if(get_integrity() < max_integrity)
		if(!density)
			to_chat(user, span_warning("\The [src] must be closed before you can repair it."))
			return ITEM_INTERACT_BLOCKING

		var/repairtime = max_integrity - get_integrity()
		use_tool(user, tool, src, delay = repairtime, quality = TOOL_WELDER, volume = 50, amount = 0, start_self = "You start to fix dents and repair \the [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done2), done_args = list(user))
		return ITEM_INTERACT_SUCCESS
	return NONE

/obj/machinery/door/proc/welder_act_tool_done(mob/user)
	to_chat(user, span_notice("You finish reinforcing \the [src]."))
	heat_proof = TRUE
	update_icon()
	set_reinforcing(0)
/obj/machinery/door/proc/welder_act_tool_done2(mob/user)
	to_chat(user, span_notice("You finish repairing the damage to \the [src]."))
	repair_damage(max_integrity)
	atom_fix()

/obj/machinery/door/proc/try_to_activate_door(mob/user)
	add_fingerprint(user)
	if(operating || isrobot(user))
		return FALSE //borgs can't attack doors open because it conflicts with their AI-like interaction with them.
	if(allowed(user) && operable())
		if(density)
			open()
		else
			close()
		return TRUE
	if(density)
		do_animate("deny")

	return FALSE

DECLARE_EMAG_REPEATABLE(/obj/machinery/door/firedoor, PROC_REF(on_emag), null)
DECLARE_EMAG_REPEATABLE(/obj/machinery/door/blast, PROC_REF(on_emag), null)
DECLARE_EMAG_REPEATABLE(/obj/machinery/door/window, PROC_REF(on_emag), null)
DECLARE_EMAG_REPEATABLE(/obj/machinery/door/unpowered, PROC_REF(on_emag), null)
/obj/machinery/door/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(density && operable())
		do_animate("spark")
		om_after(src, 0.6 SECONDS, PROC_REF(trigger_emag))
		return TRUE
