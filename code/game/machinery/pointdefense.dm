//
// Control computer for point defense batteries.
// Handles control UI, but also coordinates their fire to avoid overkill.
//

REGISTRY_MEMBERSHIP(/obj/machinery/pointdefense_control, REGISTRY_POINTDEFENSE_CONTROLLERS)
REGISTRY_MEMBERSHIP(/obj/machinery/pointdefense, REGISTRY_POINTDEFENSE_TURRETS)

/obj/machinery/pointdefense_control
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "fire assist mainframe"
	desc = "A specialized computer designed to synchronize a variety of weapon systems and a vessel's astronav data."
	icon = 'icons/obj/pointdefense.dmi'
	icon_state = "control"
	power_channel = EQUIP
	use_power = USE_POWER_ACTIVE
	active_power_usage = 5 KILOWATTS
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/pointdefense_control
	/// Meteors being engaged by associated batteries (a relation view: meteors leave when they die).
	var/list/obj/effect/meteor/targets
	var/id_tag = null

/obj/machinery/pointdefense_control/Initialize(mapload)
	. = ..()
	if(id_tag)
		//No more than 1 controller please.
		for(var/obj/machinery/pointdefense_control/PC as anything in REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_CONTROLLERS))
			if(PC != src && PC.id_tag == id_tag)
				WARNING("Two [src] with the same id_tag of [id_tag]")
				id_tag = null
	default_apply_parts()

/obj/machinery/pointdefense_control/get_description_interaction()
	. = ..()
	if(!id_tag)
		. += "[desc_panel_image("multitool")]to set ident tag"

CAPABILITIES(/obj/machinery/pointdefense_control)
	interface("PointDefenseControl")
	op("toggle_active", ui_act("toggle_active", arg("target")), then(PROC_REF(ui_act_toggle_active)))
	ref_many(nameof(targets))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))

/obj/machinery/pointdefense_control/proc/ui_act_toggle_active(datum/act/op/A, target)
	var/mob/user = A.actor
	var/obj/machinery/pointdefense/PD = ui_ref(target, null, /obj/machinery/pointdefense)
	if(!istype(PD))
		return FALSE

	if(PD.id_tag != id_tag)
		return FALSE

	if(!(get_z(PD) in GetConnectedZlevels(get_z(src))))
		to_chat(user, span_warning("[PD] is not within control range."))
		return FALSE

	if(!PD.Activate()) //Activate() whilst the device is active will return false.
		PD.Deactivate()
	return TRUE

/obj/machinery/pointdefense_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["id"] = id_tag
	var/list/turrets = list()
	if(id_tag)
		var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
		for(var/i = 1 to LAZYLEN(REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_TURRETS)))
			var/obj/machinery/pointdefense/PD = REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_TURRETS)[i]
			if(!(PD.id_tag == id_tag && (get_z(PD) in connected_z_levels)))
				continue
			var/list/turret = list()
			turret["id"] =          "#[i]"
			turret["ref"] =         "\ref[PD]"
			turret["active"] =       PD.active
			turret["effective_range"] = PD.active ? "[PD.kill_range] meter\s" : "OFFLINE."
			turret["reaction_wheel_delay"] = PD.active ? "[(PD.rotation_speed / (1 SECONDS))] second\s" : "OFFLINE."
			turret["recharge_time"] = PD.active ? "[(PD.charge_cooldown / (1 SECONDS))] second\s" : "OFFLINE."

			turrets += list(turret)

	data["turrets"] = turrets
	return data

/obj/machinery/pointdefense_control/multitool_act(mob/user, obj/item/tool)
	open_request(src, /datum/prompt/text, PROC_REF(ident_entered), answerer = user, title = "[src]", question = "Enter a new ident tag.", default = id_tag, max_len = MAX_NAME_LEN, usable_state = "physical", name_text = TRUE, timeout = 0)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/pointdefense_control/proc/ident_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_ident = A.answer.value
	if(new_ident && new_ident != id_tag && user.Adjacent(src))
		for(var/obj/machinery/pointdefense_control/PC as anything in REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_CONTROLLERS))
			if(PC != src && PC.id_tag == new_ident)
				to_chat(user, span_warning("The [new_ident] network already has a controller."))
				return ITEM_INTERACT_BLOCKING
		to_chat(user, span_notice("You register [src] with the [new_ident] network."))
		id_tag = new_ident
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

//
// The acutal point defense battery
//

/obj/machinery/pointdefense
	name = "\improper point defense battery"
	icon = 'icons/obj/pointdefense.dmi'
	icon_state = "pointdefense2"
	desc = "A Kuiper pattern anti-meteor battery. Capable of destroying most threats in a single salvo."
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/pointdefense
	maintenance_flags = MACHINE_MAINT_STANDARD
	appearance_flags = PIXEL_SCALE
	active = TRUE
	var/charge_cooldown = 1 SECOND  //time between it can fire at different targets
	EXPIRY_DECLARE(last_shot)
	var/kill_range = 18
	var/rotation_speed = 4.5 SECONDS  //How quickly we turn to face threats
	var/obj/effect/meteor/engaging = null // The meteor we're shooting at (a relation view)
	var/id_tag = null
	var/fire_sounds = SFX_WEAPONS_FRIGATE_TURRET_FRIGATE_TURRET_FIRE_MIX

/// Steps (watches for and shoots meteors) while switched on and working.
// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and redraws for them
/obj/machinery/pointdefense/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()

/obj/machinery/pointdefense/get_description_interaction()
	. = ..()
	if(!id_tag)
		. += "[desc_panel_image("multitool")]to set ident tag and connect to a mainframe."

/obj/machinery/pointdefense/proc/appearance_live()
	return (active && id_tag && operable()) ? 1 : 0

APPEARANCE_TEMPLATE(/obj/machinery/pointdefense, "{initial(icon_state)}{appearance_live?:_off}")

// Find controller with the same tag on connected z levels (if any)
/obj/machinery/pointdefense/proc/get_controller()
	if(!id_tag)
		return null
	var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
	for(var/obj/machinery/pointdefense_control/PDC as anything in REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_CONTROLLERS))
		if(PDC.id_tag == id_tag && (get_z(PDC) in connected_z_levels))
			return PDC

/obj/machinery/pointdefense/multitool_act(mob/user, obj/item/tool)
	open_request(src, /datum/prompt/text, PROC_REF(ident_entered), answerer = user, title = "[src]", question = "Enter a new ident tag.", default = id_tag, max_len = MAX_NAME_LEN, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/pointdefense/proc/ident_entered(datum/act/request/A)
	if(!A.answer)
		return ITEM_INTERACT_BLOCKING
	var/new_ident = A.answer.value
	if(new_ident && new_ident != id_tag)
		to_chat(A.request.answerer, span_notice("You register [src] with the [new_ident] network."))
		id_tag = new_ident
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

//Guns cannot shoot through hull or generally dense turfs.
/obj/machinery/pointdefense/proc/space_los(meteor)
	for(var/turf/T in getline(src,meteor))
		if(T.density)
			return FALSE
	return TRUE

/obj/machinery/pointdefense/proc/Shoot(obj/effect/meteor/M)
	if(!istype(M))
		rel_clear(src, nameof(engaging))
		return
	rel_set(src, nameof(engaging), M)
	var/Angle = round(Get_Angle(src,M))
	var/matrix/rot_matrix = matrix()
	rot_matrix.Turn(Angle)
	after(src, rotation_speed, PROC_REF(finish_shot), with = list(M))
	animate(src, transform = rot_matrix, rotation_speed, easing = SINE_EASING)

	set_dir(ATAN2(transform.b, transform.a) > 0 ? NORTH : SOUTH)

/obj/machinery/pointdefense/proc/finish_shot(obj/effect/meteor/M)

	var/obj/machinery/pointdefense_control/PC = get_controller()
	rel_clear(src, nameof(engaging))
	if(PC && M)
		rel_remove(PC, nameof(PC.targets), M)

	EXPIRY_STAMP(src, last_shot, CLOCK_WORLD)
	if(!istype(M))
		return
	//We throw a laser but it doesnt have to hit for meteor to explode
	var/obj/item/projectile/beam/coildefense/coil = new(get_turf(src))
	playsound(src, fire_sounds, 75, 1, 40, pressure_affected = FALSE, ignore_walls = TRUE)
	use_power_oneoff(idle_power_usage * 10)
	coil.launch_projectile(target = M.loc, user = src)
	after(src, 1 SECONDS, PROC_REF(fire_sound_delayed))

/obj/machinery/pointdefense/proc/fire_sound_delayed()
	playsound(src, fire_sounds, 75, 1, 40, pressure_affected = FALSE, ignore_walls = TRUE)

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/pointdefense)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(active), gate = PROC_REF(operable), wakes_on = list(nameof(active), nameof(stat)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))

/obj/machinery/pointdefense/proc/work_step(datum/act/timer/A)
	var/desiredir = ATAN2(transform.b, transform.a) > 0 ? NORTH : SOUTH
	if(dir != desiredir)
		set_dir(desiredir)

	if(!LAZYLEN(REGISTRY_MEMBERS(REGISTRY_METEORS)))
		return // no meteors about: it looks again next step
	find_and_shoot()

/obj/machinery/pointdefense/proc/find_and_shoot()
	// There ARE meteors to shoot
	if(LAZYLEN(REGISTRY_MEMBERS(REGISTRY_METEORS)) == 0)
		return
	// We can shoot
	if(engaging || (ELAPSED(src, last_shot, CLOCK_WORLD) < charge_cooldown))
		return

	var/obj/machinery/pointdefense_control/PC = get_controller()
	if(!istype(PC) || !PC.powered(EQUIP))
		return

	// Compile list of known targets
	var/list/existing_targets = list()
	for(var/obj/effect/meteor/M as anything in PC.targets)
		existing_targets += M

	// First, try and acquire new targets
	var/list/potential_targets = REGISTRY_COPY(REGISTRY_METEORS) - existing_targets
	for(var/obj/effect/meteor/M in potential_targets)
		if(targeting_check(M))
			rel_add(PC, nameof(PC.targets), M)
			Shoot(M)
			return

	// Then, focus fire on existing targets
	for(var/obj/effect/meteor/M in existing_targets)
		if(targeting_check(M))
			Shoot(M)
			return

/obj/machinery/pointdefense/proc/targeting_check(obj/effect/meteor/M)
	// Target in range
	var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
	if(!(M.z in connected_z_levels))
		return FALSE
	if(get_dist(M, src) > kill_range)
		return FALSE
	// If we can shoot it, then shoot
	if(emagged || !space_los(M))
		return FALSE

	return TRUE

/obj/machinery/pointdefense/RefreshParts()
	. = ..()
	// Calculates an average rating of components that affect shooting rate
	var/shootrate_divisor = total_component_rating_of_type(/obj/item/stock_parts/capacitor)

	charge_cooldown = 2 SECONDS / (shootrate_divisor ? shootrate_divisor : 1)

	//Calculate max shooting range
	var/killrange_multiplier = total_component_rating_of_type(/obj/item/stock_parts/capacitor)
	killrange_multiplier += 1.5 * total_component_rating_of_type(/obj/item/stock_parts/scanning_module)

	kill_range = 10 + 4 * killrange_multiplier

	var/rotation_divisor = total_component_rating_of_type(/obj/item/stock_parts/manipulator)
	rotation_speed = 4.5 SECONDS / (rotation_divisor ? rotation_divisor : 1)

/obj/machinery/pointdefense/proc/Activate()
	if(active)
		return FALSE

	play_sfx(src, SFX_WEAPONS_FLASH, vary = FALSE)
	set_active(TRUE)
	return TRUE

/obj/machinery/pointdefense/proc/Deactivate()
	if(!active)
		return FALSE
	play_sfx(src, SFX_MACHINES_APC_NOPOWER)
	set_active(FALSE)
	return TRUE

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/pointdefense/step_start_condition()
	return active && LAZYLEN(REGISTRY_MEMBERS(REGISTRY_METEORS))
