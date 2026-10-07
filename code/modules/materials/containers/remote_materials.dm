/*
This owned datum allows machines to connect remotely to a material container
(namely an /obj/machinery/ore_silo) elsewhere. It offers optional graceful
fallback to a local material storage in case remote storage is unavailable, and
handles linking back and forth.
*/

/datum/remote_materials
	// Three possible states:
	// 1. silo exists, materials is parented to silo
	// 2. silo is null, materials is owned by us (local_container)
	// 3. silo is null, materials is null

	///The silo machine this container is connected to
	var/obj/machinery/ore_silo/silo
	///Material container. the value is either the silo or local
	var/datum/material_container/mat_container
	///Should we create a local storage if we can't connect to silo
	var/allow_standalone
	///Local size of container when silo = null
	var/local_size = INFINITY
	///Flags used for the local material container(exceptions for item insert & intent flags)
	var/mat_container_flags = NONE
	///List of event path -> owner proc ref to hook onto the local container
	var/list/mat_container_events
	///The machine this connection belongs to (holds us in one of its vars; deletes us with it).
	var/atom/owner
	///Our own container when not linked to a silo (owned).
	var/datum/material_container/local_container

CAPABILITIES(/datum/remote_materials)
	owns_one(nameof(local_container), /datum/material_container)


/datum/remote_materials/New(
	atom/new_owner,
	mapload,
	allow_standalone = TRUE,
	force_connect = FALSE,
	mat_container_flags = NONE,
	list/mat_container_events = null,
)
	..()
	if (!isatom(new_owner))
		log_world("remote_materials: created without an atom owner ([new_owner])")
		return
	rel_set(src, nameof(/datum/action_group::owner), new_owner)

	src.allow_standalone = allow_standalone
	src.mat_container_flags = mat_container_flags
	src.mat_container_events = mat_container_events

	var/turf/T = get_turf(owner)
	var/connect_to_silo = FALSE
	if(force_connect || (mapload && (T.z in using_map.station_levels)))
		connect_to_silo = TRUE

	observe(owner, /datum/act/attackby, src, instead(then(PROC_REF(on_item_insert))))

	if(mapload) // wait for silo to initialize during mapload
		SSticker.OnRoundstart(src, PROC_REF(_PrepareStorage), list(connect_to_silo))
	else //directly register in round
		_PrepareStorage(connect_to_silo)

/**
 * Internal proc. prepares local storage if onnect_to_silo = FALSE
 *
 * Arguments
 * connect_to_silo- if true connect to global silo. If not successfull then go to local storage
 * only if allow_standalone = TRUE, else you a null mat_container
 */
/datum/remote_materials/proc/_PrepareStorage(connect_to_silo)
	PRIVATE_PROC(TRUE)

	if (connect_to_silo)
		rel_set(src, nameof(silo), GLOB.ore_silo_default)
		if (silo())
			rel_add(silo, nameof(silo.ore_connected_machines), src)
			rel_set(src, nameof(mat_container), silo.materials)

	if(!mat_container() && allow_standalone)
		_MakeLocal()

// disconnects from its ore silo.
/datum/remote_materials/lifecycle_dematerialize()
	..()
	if(silo())
		allow_standalone = FALSE
		disconnect()

/datum/remote_materials/proc/_MakeLocal()
	PRIVATE_PROC(TRUE)

	rel_clear(src, nameof(silo))

	rel_set(src, nameof(local_container), new /datum/material_container( \
		owner, \
		subtypesof(/datum/material), \
		local_size, \
		mat_container_flags, \
		container_events = mat_container_events, \
		allowed_items = /obj/item/stack \
	))
	rel_set(src, nameof(mat_container), local_container)

/// Adds/Removes this connection from the silo
/datum/remote_materials/proc/toggle_holding()
	if(isnull(silo()))
		return

	// silo.holds is a relation list view of the connections on hold.
	if(!(src in silo.holds))
		rel_add(silo, nameof(silo.holds), src)
	else
		rel_remove(silo, nameof(silo.holds), src)

/**
 * Sets the storage size for local materials when not linked with silo
 * Arguments
 *
 * * size - the new size for local storage. measured in SHEET_MATERIAL_SIZE units
 */
/datum/remote_materials/proc/set_local_size(size)
	local_size = size
	if (!silo() && mat_container())
		mat_container().max_amount = size

///Disconnects this connection from the silo
/datum/remote_materials/proc/disconnect()
	if(isnull(silo()))
		return

	rel_remove(silo, nameof(silo.ore_connected_machines), src)
	rel_clear(src, nameof(silo))
	rel_clear(src, nameof(mat_container))

	if (allow_standalone)
		_MakeLocal()

/datum/remote_materials/proc/OnMultitool(datum/source, mob/user, obj/item/multitool/M)
	SHOULD_NOT_SLEEP(TRUE)

	. = NONE
	if (!QDELETED(M.buffer()) && istype(M.buffer(), /obj/machinery/ore_silo))
		if (silo() == M.buffer())
			to_chat(user, span_warning("[owner] is already connected to [silo()]!"))
			return FALSE
		if(!check_z_level(M.buffer()))
			to_chat(user, span_warning("[owner] is too far away to get a connection signal!"))
			return FALSE

		var/obj/machinery/ore_silo/new_silo = M.buffer()
		var/datum/material_container/new_container = new_silo.materials
		if (silo())
			rel_remove(silo, nameof(silo.ore_connected_machines), src)
			rel_remove(silo, nameof(silo.holds), src)
		else if (mat_container())
			//transfer all mats to silo. whatever cannot be transfered is dumped out as sheets
			if(mat_container().total_amount())
				for(var/datum/material/mat as anything in mat_container().materials)
					var/mat_amount = mat_container().materials[mat]
					if(!mat_amount || !new_container.has_space(mat_amount) || !new_container.can_hold_material(mat))
						continue
					new_container.materials[mat] += mat_amount
					mat_container().materials[mat] = 0
			if(mat_container() == local_container)
				rel_clear(src, nameof(local_container)) // mat_container's view clears with it
			else
				spent(mat_container(), user)
		rel_set(src, nameof(silo), new_silo)
		rel_add(new_silo, nameof(new_silo.ore_connected_machines), src)
		rel_set(src, nameof(mat_container), new_container)
		to_chat(user, span_notice("You connect [owner] to [silo()] from the multitool's buffer."))
		return TRUE

/datum/remote_materials/proc/on_item_insert(datum/act/attackby/use)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/item/target = use.item
	var/mob/living/user = use.user
	var/obj/item/multitool/multitool = target.get_multitool()
	if(multitool)
		return OnMultitool(use.target, user, multitool) ? TRUE : HOOK_DECLINE

	if(istype(target, /obj/item/forensics))
		return HOOK_DECLINE

	if(mat_container_flags & MATCONTAINER_NO_INSERT)
		return HOOK_DECLINE

	if(istype(target, /obj/item/storage/bag/sheetsnatcher))
		mat_container().OnSheetSnatcher(use.target, user, target)
		return HOOK_DECLINE

	if(istype(target, /obj/item/gripper))
		var/obj/item/gripper/robot_gripper = target
		target = robot_gripper.get_wrapped_item()
		attempt_insert(user, target)
		return HOOK_DECLINE

	return attempt_insert(user, target) ? TRUE : HOOK_DECLINE

/// Insert mats into silo
/datum/remote_materials/proc/attempt_insert(mob/living/user, obj/item/target)
	if(silo())
		mat_container().user_insert(target, user, owner)
		return TRUE

/**
 * Checks if the param silo() is in the same level as our owner i.e. connected machine, rcd, etc
 *
 * Arguments
 * silo_to_check- Is our owner in the same Z level as this param silo(). If null
 * then check this connection's connected silo()
 *
 * Returns true if both are on the station or same z level
 */
/datum/remote_materials/proc/check_z_level(obj/silo_to_check = silo())
	if(isnull(silo_to_check))
		return FALSE

	return is_valid_z_level(get_turf(silo_to_check), get_turf(owner))

/// returns TRUE if this connection put on hold by the silo
/datum/remote_materials/proc/on_hold()
	return check_z_level() ? (src in silo().holds) : FALSE

/**
 * Check if this connection can use any materials from the silo()
 * Returns true only if
 * - The owner is of type movable atom
 * - A mat container is actually present
 * - The silo() in not on hold
 * Arguments
 * * check_hold - should we check if the silo() is on hold
 */
/datum/remote_materials/proc/can_use_resource(check_hold = TRUE)
	var/atom/movable/movable_parent = owner
	if (!istype(movable_parent))
		return FALSE
	if (!mat_container()) //no silolink & local storage not supported
		movable_parent.atom_say("No access to material storage, please contact the quartermaster.")
		return FALSE
	if(check_hold && on_hold()) //silo on hold
		movable_parent.atom_say("Mineral access is on hold, please contact the quartermaster.")
		return FALSE
	return TRUE

/**
 * Use materials from either the silo(if connected) or from the local storage. If silo() then this action
 * is logged else not e.g. action="build" & name="matter bin" means you are trying to build a matter bin
 *
 * Arguments
 * [mats][list]- list of materials to use
 * coefficient- each mat unit is scaled by this value then rounded. This value if usually your machine efficiency e.g. upgraded protolathe has reduced costs
 * multiplier- each mat unit is scaled by this value then rounded after it is scaled by coefficient. This value is your print quatity e.g. printing multiple items
 * action- For logging only. e.g. build, create, i.e. the action you are trying to perform
 * name- For logging only. the design you are trying to build e.g. matter bin, etc.
 */
/datum/remote_materials/proc/use_materials(list/mats, coefficient = 1, multiplier = 1, action = "build", name = "design")
	if(!can_use_resource())
		return 0

	var/list/rebuilt_mats = list()
	for(var/datum/material/req_mat as anything in mats)
		var/imat = mats[req_mat]
		if(!istype(req_mat))
			req_mat = GET_MATERIAL_REF(req_mat)
		rebuilt_mats[req_mat] = imat

	var/amount_consumed = mat_container().use_materials(rebuilt_mats, coefficient, multiplier)

	if (silo())//log only if silo is linked
		var/list/scaled_mats = list()
		for(var/i in rebuilt_mats)
			scaled_mats[i] = OPTIMAL_COST(OPTIMAL_COST(rebuilt_mats[i] * coefficient) * multiplier)
		silo().silo_log(owner, action, -multiplier, name, scaled_mats)

	return amount_consumed

/**
 * Ejects the given material ref and logs it
 *
 * Arguments
 * [material_ref][datum/material]- The material type you are trying to eject
 * eject_amount- how many sheets to eject
 * [drop_target][atom]- optional where to drop the sheets. null means it is dropped at our owner location
 */
/datum/remote_materials/proc/eject_sheets(datum/material/material_ref, eject_amount, atom/drop_target = null)
	if(!can_use_resource())
		return 0

	var/atom/movable/movable_parent = owner
	if(isnull(drop_target))
		drop_target = movable_parent.drop_location()

	return mat_container().retrieve_sheets(eject_amount, material_ref, target = drop_target, context = owner)

/**
 * Insert an item into the mat container, helper proc to insert items with the correct context
 *
 * Arguments
 * * obj/item/weapon - the item you are trying to insert
 * * multiplier - the multiplier applied on the materials consumed
 */
/datum/remote_materials/proc/insert_item(obj/item/weapon, multiplier = 1)
	if(!can_use_resource(FALSE))
		return MATERIAL_INSERT_ITEM_FAILURE

	return mat_container().insert_item(weapon, multiplier, owner)

/// The silo we are connected to (a relation view).
/datum/remote_materials/proc/silo() as /obj/machinery/ore_silo
	return silo

/// The material container in use (the silo's or our local one) (a relation view).
/datum/remote_materials/proc/mat_container() as /datum/material_container
	return mat_container
