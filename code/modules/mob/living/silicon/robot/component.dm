// Robot components are the robot's body parts. Each sits in a ROBOT_SLOT_* slot,
// is an affliction location on the robot's machine body, and has a graded
// function (1 - load/max) that the robot reads for movement, vision, radio
// and self-diagnosis. Destruction stays a threshold event.
//
// A component stores no damage numbers: its damage IS the load afflictions
// the body has located on it (plans/machine.dm). A removed part carries its
// afflictions away on the item (/datum/component/carried_afflictions) and
// brings them back when it is installed again, so damage is never erased.

/datum/robot_component
	var/name
	/// ROBOT_SLOT_* this component occupies.
	var/slot
	/// ROBOT_PART_INSTALLED / _MISSING / _DESTROYED.
	var/installed = ROBOT_PART_MISSING
	/// Set by the robot's power ledger: TRUE while the bus delivers power.
	var/powered = FALSE
	/// Player toggle (robot UI).
	var/toggled = TRUE
	/// Joules drawn every Life cycle while toggled on.
	var/idle_usage = 0
	/// Joules drawn per action (a step, a transmission, a scan).
	var/active_usage = 0
	/// Load at which the part is destroyed.
	var/max_damage = 30
	/// Internal parts (core, cooling) can't be pried out and aren't hit by
	/// spread damage; they are reached by their own afflictions and injuries.
	var/internal = FALSE
	var/mob/living/silicon/robot/owner
	/// The item type that installs into this slot.
	var/external_type = null
	/// The installed item (part, cell, or fried remains). Null for internal parts.
	var/obj/item/wrapped = null

/datum/robot_component/New(mob/living/silicon/robot/R, new_slot)
	owner = R
	slot = new_slot

/datum/robot_component/Destroy(force)
	if(wrapped)
		QDEL_NULL(wrapped)
	owner = null
	return ..()

/// Put `part` into this slot. Afflictions the part carried rejoin the body here.
/datum/robot_component/proc/install(obj/item/part)
	if(part)
		wrapped = part
	installed = ROBOT_PART_INSTALLED
	if(istype(wrapped, /obj/item/robot_parts/robot_component))
		var/obj/item/robot_parts/robot_component/comp = wrapped
		max_damage = comp.max_damage
		idle_usage = comp.idle_usage
		active_usage = comp.active_usage
	else if(istype(wrapped, /obj/item/cell))
		var/obj/item/cell/cell = wrapped
		max_damage = cell.robot_durability
	restore_carried_afflictions()
	owner?.on_part_changed(src)

/// Take the part out of this slot. Its afflictions leave with it.
/// Returns the removed item.
/datum/robot_component/proc/uninstall()
	SHOULD_CALL_PARENT(TRUE)
	. = wrapped
	carry_afflictions_out()
	max_damage = initial(max_damage)
	idle_usage = initial(idle_usage)
	active_usage = initial(active_usage)
	installed = ROBOT_PART_MISSING
	wrapped = null
	owner?.on_part_changed(src)

/// Threshold event: the part is fried. The remains stay installed (and keep
/// the load located here) until they are pried out.
/datum/robot_component/proc/destroy()
	SHOULD_CALL_PARENT(TRUE)
	var/brokenstate = "broken"
	if(istype(wrapped, /obj/item/robot_parts/robot_component))
		var/obj/item/robot_parts/robot_component/comp = wrapped
		brokenstate = comp.icon_state_broken
	// Clear the slot before deleting the part so deletion handlers (the
	// robot's cell watcher) see an empty slot rather than a removal.
	var/obj/item/old_part = wrapped
	wrapped = null
	if(old_part)
		qdel(old_part)
	if(!internal)
		wrapped = new /obj/item/broken_device
		wrapped.icon_state = brokenstate
	installed = ROBOT_PART_DESTROYED
	max_damage = initial(max_damage)
	idle_usage = initial(idle_usage)
	active_usage = initial(active_usage)
	log_runtime("ROBOT_PART: [owner ? key_name(owner) : "ownerless"] lost [name] (slot [slot]).")
	owner?.on_part_changed(src)

// --- Located damage -------------------------------------------------------------
// Physical load = dents and breaches; thermal load = burnt wiring.

/datum/robot_component/proc/get_robot_body()
	var/datum/body/simple/machine/robot/B = owner?.body
	return istype(B) ? B : null

/// Structural damage (dents, breaches) located on this part.
/datum/robot_component/proc/get_structural_damage()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	return B ? B.component_load(src, INJURY_CATEGORY_PHYSICAL) : 0

/// Wiring damage located on this part.
/datum/robot_component/proc/get_wiring_damage()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	return B ? B.component_load(src, INJURY_CATEGORY_THERMAL) : 0

/// Every point of load located on this part.
/datum/robot_component/proc/get_total_damage()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	return B ? B.component_load(src) : 0

/// Every affliction located on this part (load and synthetic faults).
/datum/robot_component/proc/get_afflictions()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	return B ? B.afflictions_at(src) : list()

/// Admin tool: cure everything located on this part.
/datum/robot_component/proc/clear_located_damage()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	if(!B)
		return
	for(var/datum/affliction/A as anything in B.afflictions_at(src))
		A.cure()
	B.on_status_changed()
	on_integrity_changed()

/// Admin tool: replace the located load with exact amounts. Bypasses
/// mitigation: the damage already happened.
/datum/robot_component/proc/set_located_damage(structural, wiring)
	var/datum/body/simple/machine/robot/B = get_robot_body()
	if(!B)
		return
	for(var/datum/affliction/load/L in B.afflictions_at(src))
		L.cure()
	if(structural > 0)
		var/datum/affliction/load/L = B.afflict(/datum/affliction/load/trauma, src)
		L?.receive_injury(structural, INJURY_BLUNT, null)
	if(wiring > 0)
		var/datum/affliction/load/L = B.afflict(/datum/affliction/load/burn, src)
		L?.receive_injury(wiring, INJURY_BURN, null)
	B.on_status_changed()
	on_integrity_changed()

/// Called by the robot body whenever load located here changes. An installed
/// part whose load reaches max_damage is destroyed; otherwise its graded
/// function may have changed.
/datum/robot_component/proc/on_integrity_changed()
	if(installed == ROBOT_PART_INSTALLED && get_total_damage() >= max_damage)
		destroy()
		return
	owner?.on_part_changed(src)

/// Move this slot's afflictions onto the part leaving it.
/datum/robot_component/proc/carry_afflictions_out()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	if(!B)
		return
	var/list/leaving = B.afflictions_at(src)
	if(!length(leaving))
		return
	for(var/datum/affliction/A as anything in leaving)
		B.remove_affliction(A)
		A.location = null
	if(wrapped && !QDELETED(wrapped))
		var/datum/component/carried_afflictions/carried = wrapped.AddComponent(/datum/component/carried_afflictions)
		carried?.take(leaving)
	else
		QDEL_LIST(leaving)
	B.on_status_changed()

/// Afflictions the installed part carried rejoin the body at this slot.
/datum/robot_component/proc/restore_carried_afflictions()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	if(!B || !wrapped)
		return
	var/datum/component/carried_afflictions/carried = wrapped.GetComponent(/datum/component/carried_afflictions)
	if(!carried)
		return
	for(var/datum/affliction/A as anything in carried.release())
		B.add_affliction(A, src)
	qdel(carried)
	B.on_status_changed()

// --- Function -------------------------------------------------------------------

/datum/robot_component/proc/is_intact()
	return installed == ROBOT_PART_INSTALLED && get_total_damage() < max_damage

/datum/robot_component/proc/is_powered()
	return is_intact() && (!idle_usage || powered)

/datum/robot_component/proc/is_functioning()
	return toggled && is_powered()

/// Graded function 0..1: 1 - load/max for a working part, 0 for a missing,
/// destroyed, unpowered or disabled one.
/datum/robot_component/proc/function()
	if(!is_functioning())
		return 0
	return clamp(1 - get_total_damage() / max_damage, 0, 1)

/// Joules this part draws every Life cycle while switched on.
/datum/robot_component/proc/idle_draw()
	return (toggled && is_intact()) ? idle_usage : 0

/// Ledger state change. Only the robot's power system calls this.
/datum/robot_component/proc/set_powered(new_state)
	if(powered == new_state)
		return FALSE
	powered = new_state
	return TRUE


// --- Parts ------------------------------------------------------------------------

// ACTUATOR: movement. Draws active_usage per tile.
/datum/robot_component/actuator
	name = "actuator"
	active_usage = 200
	external_type = /obj/item/robot_parts/robot_component/actuator
	max_damage = 50

/// Actuators are mechanical: they work unpowered as long as they are intact.
/datum/robot_component/actuator/is_powered()
	return is_intact()

// RADIO: idle draw for passive listening, active_usage per transmission.
/datum/robot_component/radio
	name = "radio"
	external_type = /obj/item/robot_parts/robot_component/radio
	idle_usage = 15
	active_usage = 75
	max_damage = 40

// POWER BUS: the cell mount. The cell is the installed item; the robot drops
// its cell reference when the cell is deleted (see set_cell()).
/datum/robot_component/cell
	name = "power cell"
	max_damage = 50

// DIAGNOSIS UNIT: gates self-diagnosis detail. active_usage per analysis.
/datum/robot_component/diagnosis_unit
	name = "self-diagnosis unit"
	active_usage = 1000
	external_type = /obj/item/robot_parts/robot_component/diagnosis_unit
	max_damage = 30

// CAMERA: vision and the remote camera feed.
/datum/robot_component/camera
	name = "camera"
	external_type = /obj/item/robot_parts/robot_component/camera
	idle_usage = 10
	max_damage = 40

// BINARY COMMS
/datum/robot_component/binary_communication
	name = "binary communication device"
	external_type = /obj/item/robot_parts/robot_component/binary_communication_device
	idle_usage = 5
	active_usage = 25
	max_damage = 30

// ARMOUR: soaks spread damage first. No power use.
/datum/robot_component/armour
	name = "armour plating"
	external_type = /obj/item/robot_parts/robot_component/armour
	max_damage = 90

/datum/robot_component/armour/platform
	name = "platform armour plating"
	external_type = /obj/item/robot_parts/robot_component/armour_platform
	max_damage = 140

// COOLING: the coolant loop. Internal; its circulation feeds heat debt.
/datum/robot_component/cooling
	name = "coolant loop"
	internal = TRUE
	max_damage = 60

/// Circulation 0..1: loop integrity reduced by an open coolant leak.
/datum/robot_component/cooling/proc/circulation()
	. = function()
	var/datum/body/simple/machine/robot/B = get_robot_body()
	var/datum/affliction/leak = B?.find_affliction(/datum/affliction/synthetic/coolant_leak, src)
	if(leak)
		. *= 1 - leak.severity / AFFLICTION_SEVERITY_TERMINAL

/// The loop is plumbing: it works without bus power.
/datum/robot_component/cooling/is_powered()
	return is_intact()

// CORE: processor housing. Internal; destroying it destroys the unit.
/datum/robot_component/core
	name = "processor core"
	internal = TRUE
	max_damage = 60

/datum/robot_component/core/is_powered()
	return is_intact()


// --- Robot helpers --------------------------------------------------------------------

/// Component type per slot. Subtypes override to change a part.
/mob/living/silicon/robot/proc/get_component_types()
	var/static/list/types = list(
		/datum/robot_component/actuator,
		/datum/robot_component/radio,
		/datum/robot_component/cell,
		/datum/robot_component/diagnosis_unit,
		/datum/robot_component/camera,
		/datum/robot_component/binary_communication,
		/datum/robot_component/armour,
		/datum/robot_component/cooling,
		/datum/robot_component/core,
	)
	return types

/// Build the slot list. External parts are created installed; internal parts
/// are always present; the power slot waits for set_cell().
/mob/living/silicon/robot/proc/initialize_components()
	var/list/types = get_component_types()
	components = new /list(ROBOT_SLOT_COUNT)
	for(var/slot in 1 to ROBOT_SLOT_COUNT)
		var/component_type = types[slot]
		var/datum/robot_component/C = new component_type(src, slot)
		components[slot] = C
		if(slot == ROBOT_SLOT_POWER)
			continue
		if(C.internal)
			C.installed = ROBOT_PART_INSTALLED
		else if(C.external_type)
			C.install(new C.external_type)

/mob/living/silicon/robot/proc/get_component(slot)
	return LAZYACCESS(components, slot)

/mob/living/silicon/robot/proc/is_component_functioning(slot)
	var/datum/robot_component/C = LAZYACCESS(components, slot)
	return C?.is_functioning()

/// Graded function of a slot, 0..1.
/mob/living/silicon/robot/proc/component_function(slot)
	var/datum/robot_component/C = LAZYACCESS(components, slot)
	return C ? C.function() : 0

/// Spend a part's per-action power (a transmission, a step). FALSE if the
/// part isn't working or the bus can't pay.
/mob/living/silicon/robot/proc/use_component(slot)
	var/datum/robot_component/C = LAZYACCESS(components, slot)
	if(!C?.is_functioning())
		return FALSE
	return draw_power(C.active_usage * CYBORG_POWER_USAGE_MULTIPLIER, C)


// --- Carried afflictions ------------------------------------------------------------
// Holds a removed part's afflictions while it sits outside a robot.

/datum/component/carried_afflictions
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/list/afflictions

/datum/component/carried_afflictions/Initialize()
	if(!isitem(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/carried_afflictions/Destroy(force)
	QDEL_LIST(afflictions)
	return ..()

/datum/component/carried_afflictions/proc/take(list/incoming)
	for(var/datum/affliction/A as anything in incoming)
		LAZYADD(afflictions, A)

/// Hand the afflictions back and forget them.
/datum/component/carried_afflictions/proc/release()
	. = afflictions || list()
	afflictions = null

/// Structural load the part carries (examine, installing checks).
/datum/component/carried_afflictions/proc/carried_load()
	. = 0
	for(var/datum/affliction/A as anything in afflictions)
		if(istype(A, /datum/affliction/load))
			. += A.load_value()


// --- Component objects ----------------------------------------------------------------

/obj/item/broken_device
	name = "broken component"
	icon = 'icons/obj/robot_component.dmi'
	icon_state = "broken"
	MATERIAL_BULK(MAT_STEEL, 1000)

/obj/item/broken_device/random
	var/static/list/possible_icons = list("binradio_broken",
									"motor_broken",
									"armor_broken",
									"camera_broken",
									"analyser_broken",
									"radio_broken")

/obj/item/broken_device/random/Initialize(mapload)
	icon_state = pick(possible_icons)
	. = ..()

/obj/item/robot_parts/robot_component
	icon = 'icons/obj/robot_component.dmi'
	icon_state = "working"
	var/icon_state_broken = "broken"
	var/idle_usage = 0
	var/active_usage = 0
	var/max_damage = 0

/obj/item/robot_parts/robot_component/examine(mob/user)
	. = ..()
	var/datum/component/carried_afflictions/carried = GetComponent(/datum/component/carried_afflictions)
	var/load = carried?.carried_load()
	if(load)
		. += span_warning("It is damaged ([round(load / max(max_damage, 1) * 100)]% worn).")

/obj/item/robot_parts/robot_component/binary_communication_device
	name = "binary communication device"
	desc = "A module used for binary communications over encrypted frequencies, commonly used by synthetic robots."
	icon_state = "binradio"
	icon_state_broken = "binradio_broken"
	idle_usage = 5
	active_usage = 25
	max_damage = 30

/obj/item/robot_parts/robot_component/actuator
	name = "actuator"
	desc = "A modular, hydraulic actuator used by exosuits and robots alike for movement and manipulation."
	icon_state = "motor"
	icon_state_broken = "motor_broken"
	idle_usage = 0
	active_usage = 200
	max_damage = 50

/obj/item/robot_parts/robot_component/armour
	name = "armour plating"
	desc = "A pair of flexible, adaptable armor plates, used to protect the internals of robots."
	icon_state = "armor"
	icon_state_broken = "armor_broken"
	max_damage = 90

/obj/item/robot_parts/robot_component/armour_platform
	name = "platform armour plating"
	desc = "A pair of reinforced armor plates, used to protect the internals of robots."
	icon_state = "armor"
	icon_state_broken = "armor_broken"
	color = COLOR_GRAY80
	max_damage = 140

/obj/item/robot_parts/robot_component/camera
	name = "camera"
	desc = "A modified camera module used as a visual receptor for robots and exosuits, also serving as a relay for wireless video feed."
	icon_state = "camera"
	icon_state_broken = "camera_broken"
	idle_usage = 10
	max_damage = 40

/obj/item/robot_parts/robot_component/diagnosis_unit
	name = "diagnosis unit"
	desc = "An internal computer and sensors used by robots and exosuits to accurately diagnose any system discrepancies on their components."
	icon_state = "analyser"
	icon_state_broken = "analyser_broken"
	active_usage = 1000
	max_damage = 30

/obj/item/robot_parts/robot_component/radio
	name = "radio"
	desc = "A modular, multi-frequency radio used by robots and exosuits to enable communication systems. Comes with built-in subspace receivers."
	icon_state = "radio"
	icon_state_broken = "radio_broken"
	idle_usage = 15
	active_usage = 75
	max_damage = 40

// Improved components
/obj/item/robot_parts/robot_component/binary_communication_device/upgraded
	name = "improved binary communication device"
	idle_usage = 2.5
	active_usage = 12.5
	max_damage = 45

/obj/item/robot_parts/robot_component/radio/upgraded
	name = "improved radio"
	idle_usage = 5
	active_usage = 35
	max_damage = 40

/obj/item/robot_parts/robot_component/actuator/upgraded
	name = "improved actuator"
	idle_usage = 0
	active_usage = 100
	max_damage = 75

/obj/item/robot_parts/robot_component/diagnosis_unit/upgraded
	name = "improved self-diagnosis unit"
	active_usage = 500
	max_damage = 45

/obj/item/robot_parts/robot_component/camera/upgraded
	name = "improved camera"
	idle_usage = 5
	max_damage = 60

/obj/item/robot_parts/robot_component/armour/armour_titan
	name = "prototype armour plating"
	desc = "A pair of flexible, adaptable armor plates, used to protect the internals of robots."
	max_damage = 220
	color = COLOR_OFF_WHITE
