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
	var/datum/weakref/our_owner

/obj/machinery/shield/malfai
	name = "emergency forcefield"
	desc = "A weak forcefield which seems to be projected by the station's emergency atmosphere containment field"

/obj/machinery/shield/malfai/Initialize(mapload)
	. = ..()
	update_integrity(max_integrity/2) // Half health, it's not suposed to resist much.

/obj/machinery/shield/malfai/process()
	take_damage(0.5, sound_effect = FALSE) // Slowly lose integrity over time

// A depleted shield dissipates.
/obj/machinery/shield/atom_destruction(damage_flag)
	. = ..()
	visible_message(span_boldnotice("\The [src]") + " dissipates!")
	qdel(src)

/obj/machinery/shield/Initialize(mapload)
	src.set_dir(pick(1,2,3,4))
	. = ..()
	update_nearby_tiles(need_rebuild=1)

/obj/machinery/shield/Destroy()
	opacity = 0
	density = FALSE
	update_nearby_tiles()
	var/obj/machinery/shieldgen/SG = our_owner?.resolve()
	if(SG)
		SG.deployed_shields -= src
	our_owner = null
	. = ..()

/obj/machinery/shield/attackby(obj/item/W as obj, mob/user as mob)
	if(!istype(W)) return

	//Play a fitting sound
	playsound(src, 'sound/effects/EMPulse.ogg', 75, 1)

	//Calculate damage
	if(W.obj_damage_type())
		receive_weapon_hit(W, user)

	set_opacity(1)
	spawn(20) if(!QDELETED(src)) set_opacity(0)

	..()

/obj/machinery/shield/bullet_act(obj/item/projectile/Proj)
	..()
	set_opacity(1)
	spawn(20) if(!QDELETED(src)) set_opacity(0)

/obj/machinery/shield/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	//Let everyone know we've been hit!
	visible_message(span_danger("\The [src] was hit by [source]."))

	//This seemed to be the best sound for hitting a force field.
	playsound(src, 'sound/effects/EMPulse.ogg', 100, 1)

	//The shield becomes dense to absorb the blow.. purely asthetic.
	set_opacity(1)
	spawn(20) if(!QDELETED(src)) set_opacity(0)

	..()

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
	var/active = 0
	var/malfunction = 0 //Malfunction causes parts of the shield to slowly dissapate
	var/list/deployed_shields = list()
	var/list/regenerating = list()
	var/is_open = 0 //Whether or not the wires are exposed
	var/locked = 0
	var/check_delay = 60	//periodically recheck if we need to rebuild a shield
	var/power_efficiency = 1 //Inverse. The lower, the more power efficient we are.
	use_power = USE_POWER_OFF
	idle_power_usage = 0

/obj/machinery/shieldgen/Initialize(mapload)
	. = ..()
	if(cell_type)
		cell = new cell_type(src)
	AddElement(/datum/element/climbable)

/obj/machinery/shieldgen/Destroy()
	collapse_shields()
	if(cell)
		QDEL_NULL(cell)
	if(LAZYLEN(deployed_shields))
		QDEL_NULL_LIST(deployed_shields)

	. = ..()


/obj/machinery/shieldgen/examine(mob/user)
	. = ..()
	. += "The generator is [active ? "on" : "off"] and the hatch is [is_open ? "open" : "closed"]."
	if(panel_open)
		. += "The power cell is [cell ? "installed" : "missing"]."
	else
		. += "The charge meter reads [cell ? round(cell.percent(),1) : 0]%"

/obj/machinery/shieldgen/proc/shields_up()
	if(active) return 0 //If it's already turned on, how did this get called?

	active = TRUE
	START_MACHINE_PROCESSING(src)
	update_icon()

	create_shields()

	var/new_power_usage = 0
	for(var/obj/machinery/shield/shield_tile in deployed_shields)
		new_power_usage += shield_tile.shield_idle_power

/obj/machinery/shieldgen/proc/shields_down()
	if(!active) return 0 //If it's already off, how did this get called?

	active = FALSE
	STOP_MACHINE_PROCESSING(src)
	update_icon()

	collapse_shields()

/obj/machinery/shieldgen/proc/create_shields()
	for(var/turf/target_tile in range(2, src))
		if (is_type_in_list(target_tile,GLOB.shieldgen_blockedturfs) && !(locate(/obj/machinery/shield) in target_tile))
			if (malfunction && prob(33) || !malfunction)
				var/obj/machinery/shield/S = new/obj/machinery/shield(target_tile)
				deployed_shields += S
				S.our_owner = WEAKREF(src) //So it knows to remove itself from our list when it gets qdel'd
				use_power(S.shield_generate_power)

/obj/machinery/shieldgen/proc/collapse_shields()
	for(var/obj/machinery/shield/shield_tile in deployed_shields)
		qdel(shield_tile)

/obj/machinery/shieldgen/process()
	if(!active)
		return PROCESS_KILL

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
		if(deployed_shields.len && prob(5))
			qdel(pick(deployed_shields))

// Dropping below 30% integrity makes the generator start to malfunction.
/obj/machinery/shieldgen/atom_break(damage_flag)
	. = ..()
	malfunction = TRUE
	update_icon()

// Integrity zero blows the generator apart.
/obj/machinery/shieldgen/atom_destruction(damage_flag)
	var/turf/explosion_turf = get_turf(src)
	explosion(explosion_turf, 0, 0, 1, 0, 0, 0)
	return ..()

/obj/machinery/shieldgen/ex_act(severity)
	if(severity == 2 && prob(15))
		malfunction = TRUE
	return ..()

/// EMPs eat into the generator's remaining integrity and scramble it.
/obj/machinery/shieldgen/receive_emp(severity)
	switch(severity)
		if(1)
			. = deal_damage(DAMAGE_IONIC, get_integrity() / 2, flags = DAMAGE_PACKET_SILENT) //cut health in half
			malfunction = 1
			locked = pick(0,1)
		if(2)
			if(prob(50))
				. = deal_damage(DAMAGE_IONIC, get_integrity() * 0.7, flags = DAMAGE_PACKET_SILENT) //chop off a third of the health
				malfunction = 1

/obj/machinery/shieldgen/attack_hand(mob/user as mob)
	if(locked)
		to_chat(user, "The machine is locked, you are unable to use it.")
		return
	if(is_open)
		to_chat(user, "The panel must be closed before operating this machine.")
		return

	if (src.active)
		user.visible_message(span_blue("[icon2html(src,viewers(src))] [user] deactivated the shield generator."), \
			span_blue("[icon2html(src,user.client)] You deactivate the shield generator."), \
			"You hear heavy droning fade out.")
		src.shields_down()
	else
		if(anchored)
			user.visible_message(span_blue("[icon2html(src,viewers(src))] [user] activated the shield generator."), \
				span_blue("[icon2html(src, user.client)] You activate the shield generator."), \
				"You hear heavy droning.")
			src.shields_up()
		else
			to_chat(user, "The device must first be secured to the floor.")
	return

/obj/machinery/shieldgen/emag_act(remaining_charges, mob/user)
	if(!malfunction)
		malfunction = TRUE
		update_icon()
		return 1

/obj/machinery/shieldgen/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/stack/cable_coil) && malfunction && is_open)
		var/obj/item/stack/cable_coil/coil = W
		to_chat(user, span_notice("You begin to replace the wires."))
		if(do_after(user, 3 SECONDS, target = src))
			if (coil.use(1))
				repair_damage(max_integrity)
				malfunction = 0
				to_chat(user, span_notice("You repair the [src]!"))
				update_icon()

	else if(istype(W, /obj/item/card/id) || istype(W, /obj/item/pda))
		if(src.allowed(user))
			locked = !locked
			to_chat(user, "The controls are now [src.locked ? "locked." : "unlocked."]")
		else
			to_chat(user, span_red("Access denied."))

	else if(istype(W, /obj/item/cell))
		if(is_open)
			if(cell)
				to_chat(user, "There is already a power cell inside.")
				return
			// insert cell
			var/obj/item/cell/C = user.get_active_hand()
			if(istype(C))
				user.drop_item()
				cell = C
				C.forceMove(src)
				C.add_fingerprint(user)

				user.visible_message(span_notice("[user] inserts a power cell into [src]."), span_notice("You insert the power cell into [src]."))
				power_change()
		else
			to_chat(user, "The hatch must be open to insert a power cell.")
			return
	else
		..()

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
		anchored = FALSE
	else
		if(istype(get_turf(src), /turf/space))
			return ITEM_INTERACT_BLOCKING
		playsound(src, W.usesound, 100, 1)
		to_chat(user, span_blue("You secure the [src] to the floor!"))
		anchored = TRUE
	return ITEM_INTERACT_SUCCESS


/obj/machinery/shieldgen/update_icon()
	if(active && !(stat & NOPOWER))
		src.icon_state = malfunction ? "shieldonbr":"shieldon"
	else
		src.icon_state = malfunction ? "shieldoffbr":"shieldoff"
	return
