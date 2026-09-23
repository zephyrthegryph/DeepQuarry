// The robot belly: everything the sleeper belly adds to a chassis, owned in one
// place instead of branches through the base robot.
//   - sleeper state (the belly light) and its effect on belly overlays
//   - riding
//   - ejecting the sleeper's contents on death
//   - the supply compactor's ore bag, and the bluespace pounce
// Modules attach it in /obj/item/robot_module/proc/on_robot_equip() and remove it
// on reset.

/datum/component/robot_belly
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// SLEEPER_STATE_*: drives the red/green belly light.
	var/sleeper_state = SLEEPER_STATE_EMPTY
	/// Ore bags currently autoloading (their sleeper is equipped). Lazy.
	var/list/active_ore_bags

/datum/component/robot_belly/Initialize()
	if(!isrobot(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/robot_belly/RegisterWithParent()
	var/mob/living/silicon/robot/R = parent
	R.can_buckle = TRUE
	R.buckle_movable = TRUE
	R.buckle_lying = FALSE
	R.max_buckled_mobs = 1
	if(!R.riding_datum)
		R.riding_datum = new /datum/riding/dogborg(R)
	RegisterSignal(R, COMSIG_MOB_DEATH, PROC_REF(on_death))
	RegisterSignal(R, COMSIG_ROBOT_EQUIPMENT_CHANGED, PROC_REF(on_equipment_changed))
	RegisterSignal(R, COMSIG_ROBOT_BELLY_FULLNESS, PROC_REF(on_belly_fullness))

/datum/component/robot_belly/UnregisterFromParent()
	var/mob/living/silicon/robot/R = parent
	UnregisterSignal(R, list(COMSIG_MOB_DEATH, COMSIG_ROBOT_EQUIPMENT_CHANGED, COMSIG_ROBOT_BELLY_FULLNESS))
	for(var/obj/item/ore_bag/bag as anything in active_ore_bags)
		bag.dropped(R)
	active_ore_bags = null
	for(var/rider in R.buckled_mobs)
		R.riding_datum?.force_dismount(rider)
	QDEL_NULL(R.riding_datum)
	R.can_buckle = initial(R.can_buckle)

/datum/component/robot_belly/Destroy(force)
	active_ore_bags = null
	return ..()

/// The sleeper sets this; the sprite only redraws when it actually changes.
/datum/component/robot_belly/proc/set_sleeper_state(new_state)
	if(sleeper_state == new_state)
		return FALSE
	sleeper_state = new_state
	var/mob/living/silicon/robot/R = parent
	R.update_icon()
	return TRUE

/datum/component/robot_belly/proc/get_sleepers()
	var/mob/living/silicon/robot/R = parent
	. = list()
	if(!R.module)
		return
	for(var/obj/item/dogborg/sleeper/S in R.module.modules)
		. += S
	for(var/obj/item/dogborg/sleeper/S in R.get_all_held_items())
		. |= S

/datum/component/robot_belly/proc/on_death(datum/source, gibbed)
	SIGNAL_HANDLER
	for(var/obj/item/dogborg/sleeper/S as anything in get_sleepers())
		INVOKE_ASYNC(S, TYPE_PROC_REF(/obj/item/dogborg/sleeper, go_out))

/// Ore bags autoload only while their compactor is equipped; the pounce turns
/// bluespace while anomalous sight is active.
/datum/component/robot_belly/proc/on_equipment_changed(datum/source, obj/item/changed)
	SIGNAL_HANDLER
	var/mob/living/silicon/robot/R = parent
	var/list/held = R.get_all_held_items()
	for(var/obj/item/dogborg/sleeper/S as anything in get_sleepers())
		if(!S.ore_storage || !S.ore_bag)
			continue
		var/active = (S in held)
		if(active && !(S.ore_bag in active_ore_bags))
			LAZYADD(active_ore_bags, S.ore_bag)
			S.ore_bag.equipped(R)
		else if(!active && (S.ore_bag in active_ore_bags))
			LAZYREMOVE(active_ore_bags, S.ore_bag)
			S.ore_bag.dropped(R)
	var/obj/item/dogborg/pounce/pounce = R.has_upgrade_module(/obj/item/dogborg/pounce)
	if(!pounce)
		return
	if(R.sight_mode & BORGANOMALOUS)
		pounce.name = "bluespace pounce"
		pounce.icon_state = "bluespace_pounce"
		pounce.bluespace = TRUE
	else
		pounce.name = initial(pounce.name)
		pounce.icon_state = initial(pounce.icon_state)
		pounce.desc = initial(pounce.desc)
		pounce.bluespace = initial(pounce.bluespace)

/// The "sleeper" belly class shows the sleeper's contents per the owner's
/// overlay preference.
/datum/component/robot_belly/proc/on_belly_fullness(datum/source, belly_class, list/fullness_ref)
	SIGNAL_HANDLER
	var/mob/living/silicon/robot/R = parent
	if(belly_class != "sleeper" || !R.vore_selected)
		return
	var/preference = R.vore_selected.silicon_belly_overlay_preference
	if(sleeper_state == SLEEPER_STATE_EMPTY)
		if(preference == "Sleeper")
			fullness_ref[1] = 0
		return
	var/capacity = R.vore_capacity_ex[belly_class]
	if(fullness_ref[1] + 1 > capacity)
		return
	if(preference == "Sleeper")
		fullness_ref[1] = capacity
	else if(preference == "Both")
		fullness_ref[1] += 1


// --- Riding ------------------------------------------------------------------------------------

/datum/riding/dogborg
	keytype = /obj/item/material/twohanded/riding_crop // Crack!
	nonhuman_key_exemption = FALSE	// If true, nonhumans who can't hold keys don't need them, like borgs and simplemobs.
	key_name = "a riding crop"		// What the 'keys' for the thing being rided on would be called.
	only_one_driver = TRUE			// If true, only the person in 'front' (first on list of riding mobs) can drive.

/datum/riding/dogborg/handle_vehicle_layer()
	ridden.layer = initial(ridden.layer)

/datum/riding/dogborg/ride_check(mob/living/M)
	var/mob/living/L = ridden
	if(L.stat)
		force_dismount(M)
		return FALSE
	return TRUE

/datum/riding/dogborg/force_dismount(mob/M)
	. =..()
	ridden.visible_message(span_notice("[M] stops riding [ridden]!"))

//Hoooo boy.
/datum/riding/dogborg/get_offsets(pass_index) // list(dir = x, y, layer)
	var/mob/living/L = ridden
	var/scale = L.size_multiplier
	var/scale_difference = (L.size_multiplier - rider_size) * 10

	var/list/values = list(
		"[NORTH]" = list(0, 10*scale + scale_difference, ABOVE_MOB_LAYER),
		"[SOUTH]" = list(0, 10*scale + scale_difference, BELOW_MOB_LAYER),
		"[EAST]" = list(-5*scale, 10*scale + scale_difference, ABOVE_MOB_LAYER),
		"[WEST]" = list(5*scale, 10*scale + scale_difference, ABOVE_MOB_LAYER))

	return values
