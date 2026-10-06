/obj/machinery/shield
	emp_integrity_factor = 2 // a heavy pulse (100 ionic) collapses a fresh 200-integrity field
	name = "emergency energy shield"
	desc = "An energy shield used to contain hull breaches."
	icon = 'icons/effects/effects.dmi'
	icon_state = "shield-old"
	density = TRUE
	opacity = 0
	anchored = TRUE
	unacidable = TRUE
	can_atmos_pass = ATMOS_PASS_NO
	max_integrity = 200 //The shield can only take so much beating (prevents perma-prisons)
	var/shield_generate_power = 7500	//how much power we use when regenerating
	var/shield_idle_power = 1500		//how much power we use when just being sustained.
	/// The generator that projects this tile (it owns the tile in deployed_shields).
	var/obj/machinery/shieldgen/our_owner

/obj/machinery/shield/malfai
	name = "emergency forcefield"
	desc = "A weak forcefield which seems to be projected by the station's emergency atmosphere containment field"

/obj/machinery/shield/malfai/Initialize(mapload)
	. = ..()
	update_integrity(max_integrity/2) // Half health, it's not suposed to resist much.

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/shield/malfai)
	started_work(step = PROC_REF(work_step))

/obj/machinery/shield/malfai/proc/work_step(datum/act/timer/A)
	take_damage(0.5, sound_effect = FALSE) // Slowly lose integrity over time

// A depleted shield dissipates.
/obj/machinery/shield/atom_destruction(damage_flag)
	. = ..()
	visible_message(span_boldnotice("\The [src]") + " dissipates!")
	destroyed(src)

/obj/machinery/shield/Initialize(mapload)
	src.set_dir(pick(1,2,3,4))
	. = ..()
	update_nearby_tiles(need_rebuild=1)

// leaves its generator's deployed shields (the generator is a handle).

/obj/machinery/shield/on_destroy(force)
	set_opacity(0)
	set_density(FALSE)
	update_nearby_tiles()
	..()

/obj/machinery/shield/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/shield_hit,
	)
	..()

/// Old attackby ended with a trailing return ..(): decline so the base attackby still runs.
/datum/interaction/machine_item/shield_hit
	id = "shield_hit"
	name = "Hit"
	category = INTERACTION_CAT_ATTACK
	held_type = /obj/item
	effect = /obj/machinery/shield/proc/interaction_hit

/obj/machinery/shield/proc/interaction_hit(mob/user, obj/item/W, datum/interaction/interaction)
	//Play a fitting sound
	play_sfx(src, SFX_EFFECTS_EMPULSE, 0.75)

	//Calculate damage
	if(W.obj_damage_type())
		receive_weapon_hit(W, user)

	set_opacity(1)
	after(src, 2 SECONDS, TYPE_PROC_REF(/atom, set_opacity), with = list(0))
	return FALSE

DAMAGE_REACTION_AFTER(/obj/machinery/shield, DAMAGE_PROJECTILE, PROC_REF(shield_flash_opaque))
DAMAGE_REACTION(/obj/machinery/shield, DAMAGE_THROWN, PROC_REF(shield_thrown_hit))

/// The shield flickers opaque for a moment after absorbing a hit (purely aesthetic).
/obj/machinery/shield/proc/shield_flash_opaque(datum/damage_packet/packet)
	set_opacity(1)
	after(src, 2 SECONDS, TYPE_PROC_REF(/atom, set_opacity), with = list(0))

/// A thrown hit is announced and flickers the shield, then lands as usual.
/obj/machinery/shield/proc/shield_thrown_hit(datum/damage_packet/packet)
	//Let everyone know we've been hit!
	visible_message(span_danger("\The [src] was hit by [packet.source]."))

	//This seemed to be the best sound for hitting a force field.
	play_sfx(src, SFX_EFFECTS_EMPULSE)

	//The shield becomes dense to absorb the blow.. purely asthetic.
	shield_flash_opaque(packet)

/obj/machinery/shieldgen
	emp_integrity_factor = 1
	name = "Emergency shield projector"
	desc = "Used to seal minor hull breaches."
	icon = 'icons/obj/objects.dmi'
	icon_state = "shieldoff"
	density = TRUE
	opacity = 0
	anchored = FALSE
	pressure_resistance = 2*ONE_ATMOSPHERE
	req_access = list(ACCESS_ENGINE)
	max_integrity = 100
	integrity_failure = 0.3 // starts malfunctioning at 30% integrity
	var/obj/item/cell/cell
	var/cell_type = /obj/item/cell/high
	active = 0
	var/malfunction = 0 //Malfunction causes parts of the shield to slowly dissapate
	var/list/deployed_shields
	var/list/regenerating
	var/is_open = 0 //Whether or not the wires are exposed
	locked = 0
	var/check_delay = 60	//periodically recheck if we need to rebuild a shield
	var/power_efficiency = 1 //Inverse. The lower, the more power efficient we are.
	use_power = USE_POWER_OFF
	idle_power_usage = 0

CAPABILITIES(/obj/machinery/shieldgen)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(active), wakes_on = list(nameof(active)))
	owns_many(nameof(deployed_shields))
	climb()
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell_type))

// its shields collapse.
/obj/machinery/shieldgen/on_destroy(force)
	collapse_shields()
	..()

/obj/machinery/shieldgen/examine(mob/user)
	. = ..()
	. += "The generator is [active ? "on" : "off"] and the hatch is [is_open ? "open" : "closed"]."
	if(panel_open)
		. += "The power cell is [cell ? "installed" : "missing"]."
	else
		. += "The charge meter reads [cell ? round(cell.percent(),1) : 0]%"

/obj/machinery/shieldgen/proc/shields_up()
	if(active) return 0 //If it's already turned on, how did this get called?

	set_active(TRUE)

	create_shields()

	var/new_power_usage = 0
	for(var/obj/machinery/shield/shield_tile in deployed_shields)
		new_power_usage += shield_tile.shield_idle_power

/obj/machinery/shieldgen/proc/shields_down()
	if(!active) return 0 //If it's already off, how did this get called?

	set_active(FALSE)

	collapse_shields()

/obj/machinery/shieldgen/proc/create_shields()
	for(var/turf/target_tile in range(2, src))
		if (is_type_in_list(target_tile,GLOB.shieldgen_blockedturfs) && !(locate_within(target_tile, /obj/machinery/shield)))
			if (malfunction && prob(33) || !malfunction)
				var/obj/machinery/shield/S = new/obj/machinery/shield(target_tile)
				rel_add(src, nameof(deployed_shields), S) // a destroyed tile leaves the list by itself
				rel_set(S, nameof(S.our_owner), src)
				use_power(S.shield_generate_power)

/obj/machinery/shieldgen/proc/collapse_shields()
	own_clear(src, nameof(deployed_shields), OWN_DELETE)

/obj/machinery/shieldgen/proc/work_step(datum/act/timer/A)
	if(cell && cell.charge)
		var/power_usage = 0
		for(var/obj/machinery/shield/shield_tile in deployed_shields)
			power_usage += shield_tile.shield_idle_power
		cell.use(power_usage*CELLRATE)
		if(check_delay <= 0)
			create_shields()
			check_delay = 60
		else
			check_delay--
	else
		shields_down()
		update_icon()

	if(malfunction)
		if(length(deployed_shields) && prob(5))
			spent(DEFAULTPICK(deployed_shields, null))

// Dropping below 30% integrity makes the generator start to malfunction.
/obj/machinery/shieldgen/atom_break(damage_flag)
	. = ..()
	malfunction = TRUE

// Integrity zero blows the generator apart.
/obj/machinery/shieldgen/atom_destruction(damage_flag)
	var/turf/explosion_turf = get_turf(src)
	explosion(explosion_turf, 0, 0, 1, 0, 0, 0)
	return ..()

DAMAGE_REACTION(/obj/machinery/shieldgen, DAMAGE_EXPLOSION, PROC_REF(shieldgen_blast_malfunction))

/// A heavy blast can knock the generator into malfunctioning.
/obj/machinery/shieldgen/proc/shieldgen_blast_malfunction(datum/damage_packet/packet)
	if(packet.severity == 2 && prob(15))
		malfunction = TRUE

DAMAGE_REACTION(/obj/machinery/shieldgen, DAMAGE_EMP, PROC_REF(emp_scramble))

/// EMPs eat into the generator's remaining integrity and scramble it (instead of the plain ionic hit).
/obj/machinery/shieldgen/proc/emp_scramble(datum/damage_packet/packet)
	switch(packet.severity)
		if(1)
			deal_damage(DAMAGE_IONIC, get_integrity() / 2, flags = DAMAGE_PACKET_SILENT) //cut health in half
			malfunction = 1
			set_locked(pick(0,1))
		if(2)
			if(prob(50))
				deal_damage(DAMAGE_IONIC, get_integrity() * 0.7, flags = DAMAGE_PACKET_SILENT) //chop off a third of the health
				malfunction = 1
	return DAMAGE_REACTION_BLOCK

/obj/machinery/shieldgen/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/shieldgen_repair,
		/datum/interaction/machine_item/shieldgen_toggle_lock,
		/datum/interaction/machine_item/shieldgen_insert_cell,
		/datum/interaction/machine_hand/ungated/shieldgen_toggle,
	)
	..()

/// Old attack_hand (never called ..()).
/datum/interaction/machine_hand/ungated/shieldgen_toggle
	id = "shieldgen_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/machinery/shieldgen/proc/unlocked, "the machine is locked, you are unable to use it"), REQ_ON(PRED_TARGET, /obj/machinery/shieldgen/proc/panel_closed, "the panel must be closed before operating this machine"))
	effect = /obj/machinery/shieldgen/proc/interaction_toggle

/obj/machinery/shieldgen/proc/unlocked(mob/actor, atom/target, obj/item/held)
	return !locked

/obj/machinery/shieldgen/proc/panel_closed(mob/actor, atom/target, obj/item/held)
	return !is_open

/obj/machinery/shieldgen/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if (active)
		act_message(user, null, MSG_SELF(span_blue("[icon2html(src,user.client)] You deactivate the shield generator.")), \
			MSG_OTHERS(span_blue("[icon2html(src,viewers(src))] %U% deactivated the shield generator.")), \
			MSG_BLIND("You hear heavy droning fade out."))
		shields_down()
	else
		if(anchored)
			act_message(user, null, MSG_SELF(span_blue("[icon2html(src, user.client)] You activate the shield generator.")), \
				MSG_OTHERS(span_blue("[icon2html(src,viewers(src))] %U% activated the shield generator.")), \
				MSG_BLIND("You hear heavy droning."))
			shields_up()
		else
			to_chat(user, "The device must first be secured to the floor.")
	return TRUE

DECLARE_EMAG_REPEATABLE(/obj/machinery/shieldgen, PROC_REF(on_emag), null)
/obj/machinery/shieldgen/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(!malfunction)
		malfunction = TRUE
		update_icon()
		return 1

/datum/interaction/machine_item/shieldgen_repair
	id = "shieldgen_repair"
	name = "Repair wiring"
	category = INTERACTION_CAT_REPAIR
	held_type = /obj/item/stack/cable_coil
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/shieldgen/proc/needs_repair, null))
	effect = /obj/machinery/shieldgen/proc/interaction_repair

/obj/machinery/shieldgen/proc/needs_repair(mob/actor, atom/target, obj/item/held)
	return malfunction && is_open

/obj/machinery/shieldgen/proc/interaction_repair(mob/user, obj/item/stack/cable_coil/coil, datum/interaction/interaction)
	to_chat(user, span_notice("You begin to replace the wires."))
	om_task_timed(user, 3 SECONDS, src, src, PROC_REF(rewire_done), list(user, coil))
	return TRUE

/obj/machinery/shieldgen/proc/rewire_done(mob/user, obj/item/stack/cable_coil/coil)
	if (coil.use(1))
		repair_damage(max_integrity)
		malfunction = 0
		to_chat(user, span_notice("You repair the [src]!"))
		update_icon()

/datum/interaction/machine_item/shieldgen_toggle_lock
	id = "shieldgen_toggle_lock"
	name = "Toggle lock"
	category = INTERACTION_CAT_LOCK
	held_type = list(/obj/item/card/id, /obj/item/pda)
	effect = /obj/machinery/shieldgen/proc/interaction_toggle_lock

/obj/machinery/shieldgen/proc/interaction_toggle_lock(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		set_locked(!locked)
		to_chat(user, "The controls are now [locked ? "locked." : "unlocked."]")
	else
		to_chat(user, span_red("Access denied."))
	return TRUE

/datum/interaction/machine_item/shieldgen_insert_cell
	id = "shieldgen_insert_cell"
	name = "Insert cell"
	held_type = /obj/item/cell
	effect = /obj/machinery/shieldgen/proc/interaction_insert_cell

/obj/machinery/shieldgen/proc/interaction_insert_cell(mob/user, obj/item/cell/held, datum/interaction/interaction)
	if(is_open)
		if(cell)
			to_chat(user, "There is already a power cell inside.")
			return TRUE
		// insert cell
		var/obj/item/cell/C = user.get_active_hand()
		if(istype(C))
			if(!move_into(src, nameof(src.cell), C, user))
				return TRUE
			C.add_fingerprint(user)

			act_message(user, src, MSG_SELF(span_notice("You insert the power cell into %T%.")), MSG_OTHERS(span_notice("%U% inserts a power cell into %T%.")))
			power_change()
	else
		to_chat(user, "The hatch must be open to insert a power cell.")
		return TRUE
	return TRUE

/obj/machinery/shieldgen/screwdriver_act(mob/user, obj/item/W)
	playsound(src, W.usesound, 100, 1)
	is_open = !is_open
	to_chat(user, span_blue("You [is_open ? "open the panel and expose the wiring" : "close the panel"]."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/shieldgen/wrench_act(mob/user, obj/item/W)
	if(locked)
		to_chat(user, "The bolts are covered, unlocking this would retract the covers.")
		return ITEM_INTERACT_BLOCKING
	if(anchored)
		playsound(src, W.usesound, 100, 1)
		to_chat(user, span_blue("You unsecure the [src] from the floor!"))
		if(active)
			to_chat(user, span_blue("The [src] shuts off!"))
			shields_down()
		set_anchored(FALSE)
	else
		if(istype(get_turf(src), /turf/space))
			return ITEM_INTERACT_BLOCKING
		playsound(src, W.usesound, 100, 1)
		to_chat(user, span_blue("You secure the [src] to the floor!"))
		set_anchored(TRUE)
	return ITEM_INTERACT_SUCCESS

/// Appearance reader: projecting (active and powered).
/obj/machinery/shieldgen/proc/appearance_projecting()
	return active && !has_stat(NOPOWER)

APPEARANCE_TEMPLATE(/obj/machinery/shieldgen, "shield{appearance_projecting?on:off}{malfunction?br:}")
