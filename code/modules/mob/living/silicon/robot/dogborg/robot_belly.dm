// The robot belly: everything the sleeper belly adds to a chassis, owned in one
// place instead of branches through the base robot.
//   - sleeper state (the belly light) and its effect on belly overlays
//   - riding
//   - ejecting the sleeper's contents on death
//   - the supply compactor's ore bag, and the bluespace pounce
// Modules create it in /obj/item/robot_module/proc/on_robot_equip() and delete it
// on reset. Owned by the robot's `robot_belly` var (was /datum/robot_belly).

/datum/robot_belly
	/// The chassis this belly belongs to.
	var/mob/living/silicon/robot/owner
	/// SLEEPER_STATE_*: drives the red/green belly light.
	var/sleeper_state = SLEEPER_STATE_EMPTY
	/// Ore bags currently autoloading (their sleeper is equipped). Lazy.
	var/list/active_ore_bags

/mob/living/silicon/robot/var/datum/robot_belly/robot_belly

/datum/robot_belly/New(mob/living/silicon/robot/R)
	..()
	if(!isrobot(R))
		log_runtime("robot_belly created for a non-robot ([R]).")
		return
	rel_set(src, nameof(owner), R)
	R.set_can_buckle(TRUE)
	R.buckle_movable = TRUE
	R.buckle_lying = FALSE
	R.max_buckled_mobs = 1
	if(!R.riding_datum)
		rel_set(R, nameof(R.riding_datum), new /datum/riding/dogborg(R))
	observe(R, /datum/notice/mob_death, src, then(PROC_REF(on_death)))
	observe(R, /datum/notice/robot_equipment_changed, src, then(PROC_REF(on_equipment_changed)))
	observe(R, /datum/notice/robot_belly_fullness, src, then(PROC_REF(on_belly_fullness)))

// owned state datum (was a component): its riders and ore bags are let go.
/datum/robot_belly/on_destroy(force)
	var/mob/living/silicon/robot/R = owner
	if(R)
		for(var/obj/item/ore_bag/bag as anything in active_ore_bags)
			bag.dropped(R)
		for(var/rider in R.buckled_mob_list())
			R.riding_datum?.force_dismount(rider)
		own_clear(R, nameof(R.riding_datum), OWN_DELETE)
		R.set_can_buckle(initial(R.can_buckle))
	..()

/// Gives `R` a robot belly if it has none.
/mob/living/silicon/robot/proc/add_robot_belly()
	if(!robot_belly)
		rel_set(src, nameof(robot_belly), new /datum/robot_belly(src))
	return robot_belly

/// The sleeper sets this; the robot's look watches it, so the sprite redraws when it changes.
TRACKED(/datum/robot_belly, sleeper_state)

/datum/robot_belly/proc/get_sleepers()
	var/mob/living/silicon/robot/R = owner
	. = list()
	if(!R.module)
		return
	for(var/obj/item/dogborg/sleeper/S in R.module.modules)
		. += S
	for(var/obj/item/dogborg/sleeper/S in R.get_all_held_items())
		. |= S

/datum/robot_belly/proc/on_death(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	for(var/obj/item/dogborg/sleeper/S as anything in get_sleepers())
		S.go_out()

/// Ore bags autoload only while their compactor is equipped; the pounce turns
/// bluespace while anomalous sight is active.
/datum/robot_belly/proc/on_equipment_changed(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/silicon/robot/R = owner
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
/datum/robot_belly/proc/on_belly_fullness(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/robot_belly_fullness/event = A
	var/belly_class = event.belly_class
	var/list/fullness_ref = event.fullness_ref
	var/mob/living/silicon/robot/R = owner
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
	ridden().restore_initial_layer()

/datum/riding/dogborg/ride_check(mob/living/M)
	var/mob/living/L = ridden()
	if(L.stat)
		force_dismount(M)
		return FALSE
	return TRUE

/datum/riding/dogborg/force_dismount(mob/M)
	. =..()
	ridden().visible_message(span_notice("[M] stops riding [ridden()]!"))

//Hoooo boy.
/datum/riding/dogborg/get_offsets(pass_index) // list(dir = x, y, layer)
	var/mob/living/L = ridden()
	var/scale = L.size_multiplier
	var/scale_difference = (L.size_multiplier - rider_size) * 10

	var/list/values = list(
		"[NORTH]" = list(0, 10*scale + scale_difference, ABOVE_MOB_LAYER),
		"[SOUTH]" = list(0, 10*scale + scale_difference, BELOW_MOB_LAYER),
		"[EAST]" = list(-5*scale, 10*scale + scale_difference, ABOVE_MOB_LAYER),
		"[WEST]" = list(5*scale, 10*scale + scale_difference, ABOVE_MOB_LAYER))

	return values
