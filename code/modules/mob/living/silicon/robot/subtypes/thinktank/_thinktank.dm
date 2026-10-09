// Spawner landmarks are used because platforms that are mapped during
// SSatoms init try to Initialize() twice. I have no idea why and I am
// not paid enough to spend more time trying to debug it.
/obj/effect/landmark/robot_platform
	name = "recon platform spawner"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x3"
	delete_me = TRUE
	var/platform_type

/obj/effect/landmark/robot_platform/Initialize(mapload)
	if(platform_type)
		new platform_type(get_turf(src))
	return ..()

/mob/living/silicon/robot/platform
	name = "support platform"
	desc = "A large quadrupedal AI platform, colloquially known as a 'think-tank' due to the flexible onboard intelligence."
	icon = 'icons/mob/robots_thinktank.dmi'
	icon_state = "tachi"

	cell_type =   /obj/item/cell/mech
	module =      /obj/item/robot_module/robot/platform

	lawupdate = FALSE
	modtype = "Standard"
	speak_statement = "chirps"

	mob_bump_flag =   HEAVY
	mob_swap_flags = ~HEAVY
	mob_push_flags =  HEAVY
	mob_size =        MOB_LARGE

	var/has_had_player = FALSE
	var/const/platform_respawn_time = 3 MINUTES

	var/tmp/last_recharge_state =     FALSE
	var/tmp/recharge_complete =       FALSE
	var/tmp/recharger_charge_amount = 10 KILOWATTS
	var/tmp/recharger_tick_cost =     80 KILOWATTS
	/// The cell in the recharging port (in our contents).
	var/obj/item/cell/recharging

	/// Cargo in our contents.
	var/list/stored_atoms
	var/max_stored_atoms = 1
	var/static/list/can_store_types = list(
		/mob/living,
		/obj/item,
		/obj/structure,
		/obj/machinery
	)
	// Currently set to prevent tonks hauling a deliaminating SM into the middle of the station.
	var/static/list/cannot_store_types = list(
		/obj/machinery/power/supermatter
	)

/mob/living/silicon/robot/platform/relations()
	. = ..()
	. += rel_one(nameof(recharging))
	. += rel_many(nameof(stored_atoms))

/mob/living/silicon/robot/platform/Login()
	. = ..()
	has_had_player = TRUE

/mob/living/silicon/robot/platform/SetName(pickedName)
	. = ..()
	if(mind)
		mind.name = real_name

/mob/living/silicon/robot/platform/Initialize(mapload)
	. = ..()
	SetName("inactive [initial(name)]")
	grant(src, platform_cargo(), src)

/// Platforms carry heavier armour plating (the ROBOT_SLOT_ARMOUR entry).
TYPE_TABLE(/mob/living/silicon/robot/platform, robot_component_types, list( \
	/datum/robot_component/actuator, \
	/datum/robot_component/radio, \
	/datum/robot_component/cell, \
	/datum/robot_component/diagnosis_unit, \
	/datum/robot_component/camera, \
	/datum/robot_component/binary_communication, \
	/datum/robot_component/armour/platform, \
	/datum/robot_component/cooling, \
	/datum/robot_component/core, \
))

// Stored atoms and the recharging cell drop out.
/mob/living/silicon/robot/platform/on_destroy(force)
	revoke(src, platform_cargo(), src)
	for(var/atom/movable/drop_atom as anything in stored_atoms?.Copy())
		if(!QDELETED(drop_atom) && drop_atom.loc == src)
			drop_atom.dropInto(loc)
	var/obj/item/recharging_atom = recharging
	if(recharging_atom && recharging_atom.loc == src)
		recharging_atom.dropInto(loc)
	..()

/mob/living/silicon/robot/platform/examine(mob/user, distance)
	. = ..()
	if(distance <= 3)

		if(recharging)
			var/obj/item/cell/recharging_atom = recharging
			if(!QDELETED(recharging_atom))
				. += "It has \a [recharging_atom] slotted into its recharging port."
				. += "The cell readout shows [round(recharging_atom.percent(),1)]% charge."
			else
				. += "Its recharging port is empty."
		else
			. += "Its recharging port is empty."

		if(length(stored_atoms))
			var/list/atom_names = list()
			for(var/atom/movable/AM as anything in stored_atoms)
				atom_names += "\a [AM]"
			if(length(atom_names))
				. += "It has [english_list(atom_names)] loaded into its transport bay."
		else
			. += "Its cargo bay is empty."

/mob/living/silicon/robot/platform/update_braintype()
	braintype = BORG_BRAINTYPE_PLATFORM

/mob/living/silicon/robot/platform/setup_module()
	..()
	if(ispath(module, /obj/item/robot_module))
		rel_set(src, nameof(module), new module(src))

/mob/living/silicon/robot/platform/module_reset(notify = TRUE)
	return FALSE

/// Solar top-up and the cargo recharging port, through the power ledger.
/mob/living/silicon/robot/platform/process_power()
	. = ..()

	if(stat != DEAD && cell)

		// TODO generalize solar occlusion to charge from the actual sun.
		var/turf/T = get_turf(src)
		var/new_recharge_state = T?.is_outdoors() || isspace(T)
		if(new_recharge_state != last_recharge_state)
			last_recharge_state = new_recharge_state
			if(last_recharge_state)
				to_chat(src, span_boldnotice("Your integrated solar panels begin recharging your battery."))
			else
				to_chat(src, span_danger("Your integrated solar panels cease recharging your battery."))

		if(last_recharge_state)
			var/stored = add_power(recharger_charge_amount, src)
			module.respawn_consumable(src, (stored * CELLRATE / 250)) // magic number copied from borg charger.

		if(recharging)

			var/obj/item/cell/recharging_atom = recharging
			if(QDELETED(recharging_atom) || recharging_atom.loc != src)
				rel_clear(src, nameof(recharging))
				return

			if(recharging_atom.percent() < 100)
				// Don't kill ourselves recharging the battery: keep half a transfer in reserve.
				if(draw_power(recharger_tick_cost, recharging_atom, recharger_tick_cost * 0.5))
					recharging_atom.give(recharger_tick_cost * CELLRATE)

			if(!recharge_complete && recharging_atom.percent() >= 100)
				recharge_complete = TRUE
				act_message(src, null, others = span_infoplain("[span_bold("%U%")] beeps and flashes a green light above \his recharging port."))

/mob/living/silicon/robot/platform/ownership()
	. = ..()
	. += owns(nameof(mmi), policy = OWN_CONTAINED, starts = /obj/item/mmi/digital/robot)

