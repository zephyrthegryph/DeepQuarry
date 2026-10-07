//DO NOT ADD MECHA PARTS TO THE GAME WITH THE DEFAULT "SPRITE ME" SPRITE!
//I'm annoyed I even have to tell you this! SPRITE FIRST, then commit.

/obj/item/mecha_parts/mecha_equipment
	name = "mecha equipment"
	icon = 'icons/mecha/mecha_equipment.dmi'
	icon_state = "mecha_equip"
	force = 5
	var/equip_cooldown = 0
	var/equip_ready = TRUE
	var/energy_drain = 0
	var/range = MECH_MELEE //bitflags
	/// Bitflag. Used by exosuit fabricator to assign sub-categories based on which exosuits can equip this.
	var/mech_flags = NONE
	var/salvageable = TRUE
	var/required_type = /obj/mecha //may be either a type or a list of allowed types
	var/equip_type = null //mechaequip2
	var/allow_duplicate = FALSE
	var/ready_sound = SFX_MECHA_MECH_RELOAD_DEFAULT //Sound to play once the fire delay passed.
	var/enable_special = FALSE	// Will the tool do its special?

	var/step_delay = 0	// Does the component slow/speed up the suit?

/// The mech this is mounted on. A field: equipment declares its periodic work on it.
OM_FIELD_VIEW(/obj/item/mecha_parts/mecha_equipment, obj/mecha, chassis, CHANGE_EXPLICIT)

/// Starts the equipment cooldown (ready again after equip_cooldown). TRUE while it can act on
/// `target`: the act no longer waits for the cooldown.
/obj/item/mecha_parts/mecha_equipment/proc/do_after_cooldown(target=1)
	after(src, equip_cooldown, PROC_REF(cooldown_over))
	if(target && chassis)
		return 1
	return 0

/// The cooldown without waiting for it: ready again after equip_cooldown.
/obj/item/mecha_parts/mecha_equipment/proc/start_cooldown()
	after(src, equip_cooldown, PROC_REF(cooldown_over))

/obj/item/mecha_parts/mecha_equipment/proc/cooldown_over()
	set_ready_state(TRUE)
	if(ready_sound) //Kind of like the kinetic accelerator.
		playsound(src, ready_sound, 50, 1, -1)

/obj/item/mecha_parts/mecha_equipment/examine(mob/user)
	. = ..()
	. += span_notice("[src] will fill [equip_type?"a [equip_type]":"any"] slot.")

/obj/item/mecha_parts/mecha_equipment/proc/add_equip_overlay(obj/mecha/M as obj)
	return

/obj/item/mecha_parts/mecha_equipment/proc/update_chassis_page()
	if(chassis)
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","eq_list",chassis.get_equipment_list())
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","equipment_menu",chassis.get_equipment_menu(),"dropdowns")
		return 1
	return

/obj/item/mecha_parts/mecha_equipment/proc/update_equip_info()
	if(chassis)
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",get_equip_info())
		return 1
	return

/obj/item/mecha_parts/mecha_equipment/proc/destroy()//missiles detonating, teleporter creating singularity?
	if(chassis)
		if(equip_type)
			if(equip_type == EQUIP_HULL)
				rel_remove(chassis, nameof(chassis.hull_equipment), src)
				listclearnulls(chassis.hull_equipment)
			if(equip_type == EQUIP_WEAPON)
				rel_remove(chassis, nameof(chassis.weapon_equipment), src)
				listclearnulls(chassis.weapon_equipment)
			if(equip_type == EQUIP_UTILITY)
				rel_remove(chassis, nameof(chassis.utility_equipment), src)
				listclearnulls(chassis.utility_equipment)
			if(equip_type == EQUIP_SPECIAL)
				rel_remove(chassis, nameof(chassis.special_equipment), src)
				listclearnulls(chassis.special_equipment)
			// ition begin: MICROMECHS
			if(equip_type == EQUIP_MICRO_UTILITY)
				rel_remove(chassis, nameof(chassis.micro_utility_equipment), src)
				listclearnulls(chassis.micro_utility_equipment)
			if(equip_type == EQUIP_MICRO_WEAPON)
				rel_remove(chassis, nameof(chassis.micro_weapon_equipment), src)
				listclearnulls(chassis.micro_weapon_equipment)
			// ition end: MICROMECHS
		rel_remove(chassis, nameof(chassis.universal_equipment), src)
		rel_remove(chassis, nameof(chassis.equipment), src)
		listclearnulls(chassis.equipment)
		if(chassis.selected == src)
			rel_clear(chassis, nameof(chassis.selected))
		src.update_chassis_page()
		chassis.occupant_message(span_red("The [src] is destroyed!"))
		chassis.log_append_to_last("[src] is destroyed.",1)
		if(istype(src, /obj/item/mecha_parts/mecha_equipment/weapon))//Gun
			switch(chassis.mech_faction)
				if(MECH_FACTION_NT)
					src.chassis?.slot_item(MECHA_SLOT_PILOT) << sound('sound/mecha/weapdestrnano.ogg',volume=70)
				if(MECH_FACTION_SYNDI)
					src.chassis?.slot_item(MECHA_SLOT_PILOT)  << sound('sound/mecha/weapdestrsyndi.ogg',volume=60)
				else
					src.chassis?.slot_item(MECHA_SLOT_PILOT)  << sound('sound/mecha/weapdestr.ogg',volume=50)
		else //Not a gun
			switch(chassis.mech_faction)
				if(MECH_FACTION_NT)
					src.chassis?.slot_item(MECHA_SLOT_PILOT)  << sound('sound/mecha/critdestrnano.ogg',volume=70)
				if(MECH_FACTION_SYNDI)
					src.chassis?.slot_item(MECHA_SLOT_PILOT)  << sound('sound/mecha/critdestrsyndi.ogg',volume=70)
				else
					src.chassis?.slot_item(MECHA_SLOT_PILOT)  << sound('sound/mecha/critdestr.ogg',volume=50)
	expire(0)
	return

/obj/item/mecha_parts/mecha_equipment/proc/critfail()
	if(chassis)
		src.mecha_log_message("Critical failure",1)
	return

/obj/item/mecha_parts/mecha_equipment/proc/get_equip_info()
	if(!chassis) return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[chassis.selected==src?"<b>":"<a href='byond://?src=\ref[chassis];select_equip=\ref[src]'>"][src.name][chassis.selected==src?"</b>":"</a>"]"

/obj/item/mecha_parts/mecha_equipment/proc/is_ranged()//add a distance restricted equipment. Why not?
	return range&RANGED

/obj/item/mecha_parts/mecha_equipment/proc/is_melee()
	return range&MECH_MELEE

/obj/item/mecha_parts/mecha_equipment/proc/enable_special_checks(atom/target)
	if(ispath(required_type))
		return istype(target, required_type)

	for (var/path in required_type)
		if (istype(target, path))
			return 1

	return 0

/obj/item/mecha_parts/mecha_equipment/proc/action_checks(atom/target)
	if(!target)
		return 0
	if(!chassis)
		return 0
	if(!equip_ready)
		return 0
	if(energy_drain && !chassis.has_charge(energy_drain))
		return 0
	return 1

/obj/item/mecha_parts/mecha_equipment/proc/action(atom/target, params, mob/user = null)
	return

/obj/item/mecha_parts/mecha_equipment/proc/can_attach(obj/mecha/M as obj)
	if(!allow_duplicate)
		for(var/obj/item/mecha_parts/mecha_equipment/ME in M.equipment) //Exact duplicate components aren't allowed.
			if(ME.type == src.type)
				return 0
	if(equip_type == EQUIP_HULL && length(M.hull_equipment) < M.max_hull_equip)
		return 1
	if(equip_type == EQUIP_WEAPON && length(M.weapon_equipment) < M.max_weapon_equip)
		return 1
	if(equip_type == EQUIP_UTILITY && length(M.utility_equipment) < M.max_utility_equip)
		return 1
	if(equip_type == EQUIP_SPECIAL && length(M.special_equipment) < M.max_special_equip)
		return 1
	// ition begin: MICROMECHS
	if(equip_type == EQUIP_MICRO_UTILITY && length(M.micro_utility_equipment) < M.max_micro_utility_equip)
		return 1
	if(equip_type == EQUIP_MICRO_WEAPON && length(M.micro_weapon_equipment) < M.max_micro_weapon_equip)
		return 1
	// ition end: MICROMECHS
	if(equip_type != EQUIP_SPECIAL && length(M.universal_equipment) < M.max_universal_equip) //The exosuit needs to be military grade to actually have a universal slot capable of accepting a true weapon.
		if(equip_type == EQUIP_WEAPON && !istype(M, /obj/mecha/combat))
			return 0
		return 1
	return 0

/obj/item/mecha_parts/mecha_equipment/proc/attach(obj/mecha/M as obj)
	var/has_equipped = 0
	if(equip_type == EQUIP_HULL && length(M.hull_equipment) < M.max_hull_equip && !has_equipped)
		rel_add(M, nameof(M.hull_equipment), src)
		has_equipped = 1
	if(equip_type == EQUIP_WEAPON && length(M.weapon_equipment) < M.max_weapon_equip && !has_equipped)
		rel_add(M, nameof(M.weapon_equipment), src)
		has_equipped = 1
	if(equip_type == EQUIP_UTILITY && length(M.utility_equipment) < M.max_utility_equip && !has_equipped)
		rel_add(M, nameof(M.utility_equipment), src)
		has_equipped = 1
	if(equip_type == EQUIP_SPECIAL && length(M.special_equipment) < M.max_special_equip && !has_equipped)
		rel_add(M, nameof(M.special_equipment), src)
		has_equipped = 1
	// ition begin: MICROMECHS
	if(equip_type == EQUIP_MICRO_UTILITY && length(M.micro_utility_equipment) < M.max_micro_utility_equip && !has_equipped)
		rel_add(M, nameof(M.micro_utility_equipment), src)
		has_equipped = 1
	if(equip_type == EQUIP_MICRO_WEAPON && length(M.micro_weapon_equipment) < M.max_micro_weapon_equip && !has_equipped)
		rel_add(M, nameof(M.micro_weapon_equipment), src)
		has_equipped = 1
	// ition end: MICROMECHS
	if(equip_type != EQUIP_SPECIAL && length(M.universal_equipment) < M.max_universal_equip && !has_equipped)
		rel_add(M, nameof(M.universal_equipment), src)
	rel_add(M, nameof(M.equipment), src)
	rel_set(src, nameof(chassis), M)
	if(!move_into(M, MECHA_SLOT_EQUIPMENT, src))
		forceMove(M) // the equipment lists above already committed; guarantee the move

	if(enable_special_checks(M))
		enable_special = TRUE

	M.mecha_log_message("[src] initialized.")
	if(!M.selected)
		rel_set(M, nameof(M.selected), src)
	src.update_chassis_page()
	return

// equipment detaches from its mech.
/obj/item/mecha_parts/mecha_equipment/on_destroy(force)
	detach()
	..()

/obj/item/mecha_parts/mecha_equipment/proc/detach(atom/moveto=null)
	if(!chassis || !get_turf(chassis)) // don't detach components in nullspace
		return
	moveto = moveto || get_turf(chassis)
	if(!chassis.slot_remove(src, moveto))
		forceMove(moveto)
	rel_remove(chassis, nameof(chassis.equipment), src)
	rel_remove(chassis, nameof(chassis.universal_equipment), src)
	if(equip_type)
		switch(equip_type)
			if(EQUIP_HULL)
				rel_remove(chassis, nameof(chassis.hull_equipment), src)
			if(EQUIP_WEAPON)
				rel_remove(chassis, nameof(chassis.weapon_equipment), src)
			if(EQUIP_UTILITY)
				rel_remove(chassis, nameof(chassis.utility_equipment), src)
			if(EQUIP_SPECIAL)
				rel_remove(chassis, nameof(chassis.special_equipment), src)
			// ition begin: MICROMECHS
			if(EQUIP_MICRO_UTILITY)//CHOMPstation edit - This was improperly named bugging detaching on my equipment fix.
				rel_remove(chassis, nameof(chassis.micro_utility_equipment), src)
			if(EQUIP_MICRO_WEAPON)
				rel_remove(chassis, nameof(chassis.micro_weapon_equipment), src)
			// ition end: MICROMECHS
	if(chassis.selected == src)
		rel_clear(chassis, nameof(chassis.selected))
	update_chassis_page()
	chassis.mecha_log_message("[src] removed from equipment.")
	rel_clear(src, nameof(chassis))
	set_ready_state(TRUE)
	enable_special = FALSE
	return

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment)
	op("detach", topic("detach"), then(PROC_REF(topic_detach)))

// Equipment hrefs come from the exosuit's control panel: only its conscious pilot uses them.
/obj/item/mecha_parts/mecha_equipment/topic_allowed(mob/user, list/href_list)
	if(!chassis || !user || user.stat)
		return FALSE
	return user == chassis.slot_item(MECHA_SLOT_PILOT)

/obj/item/mecha_parts/mecha_equipment/proc/topic_detach(datum/act/op/A)
	detach()

/obj/item/mecha_parts/mecha_equipment/proc/set_ready_state(state)
	equip_ready = state
	if(chassis)
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
	return

/obj/item/mecha_parts/mecha_equipment/proc/occupant_message(message)
	if(chassis)
		var/mob/living/_tmp_occ_3 = chassis?.slot_item(MECHA_SLOT_PILOT)
		chassis.occupant_message("[icon2html(src, _tmp_occ_3?.client)] [message]")
	return

/obj/item/mecha_parts/mecha_equipment/proc/mecha_log_message(message)
	if(chassis)
		chassis.mecha_log_message("<i>[src]:</i> [message]")
	return

/obj/item/mecha_parts/mecha_equipment/proc/MoveAction() //Allows mech equipment to do an action upon the mech moving
	return

/obj/item/mecha_parts/mecha_equipment/proc/get_step_delay() // Equipment returns its slowdown or speedboost.
	return step_delay

// Read by detach() in Destroy().
