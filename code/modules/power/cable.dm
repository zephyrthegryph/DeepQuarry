///////////////////////////////
//CABLE STRUCTURE
///////////////////////////////

////////////////////////////////
// Definitions
////////////////////////////////

/** Cable directions (d1 and d2)
 *
 *
 *  9   1   5
 *	  \ | /
 *  8 - 0 - 4,
 *	  / | \
 *  10  2   6

If d1 = 0 and d2 = 0, there's no cable
If d1 = 0 and d2 = dir, it's a O-X cable, getting from the center of the tile to dir (knot cable)
If d1 = dir1 and d2 = dir2, it's a full X-X cable, getting from dir1 to dir2
By design, d1 is the smallest direction and d2 is the highest
*/
GLOBAL_LIST_INIT(possible_cable_coil_colours, list(
		"White" = COLOR_WHITE,
		"Silver" = COLOR_SILVER,
		"Gray" = COLOR_GRAY,
		"Black" = COLOR_BLACK,
		"Red" = COLOR_RED,
		"Maroon" = COLOR_MAROON,
		"Yellow" = COLOR_YELLOW,
		"Olive" = COLOR_OLIVE,
		"Lime" = COLOR_GREEN,
		"Green" = COLOR_LIME,
		"Cyan" = COLOR_CYAN,
		"Teal" = COLOR_TEAL,
		"Blue" = COLOR_BLUE,
		"Navy" = COLOR_NAVY,
		"Pink" = COLOR_PINK,
		"Purple" = COLOR_PURPLE,
		"Orange" = COLOR_ORANGE,
		"Beige" = COLOR_BEIGE,
		"Brown" = COLOR_BROWN
	))

/obj/structure/cable
	material_template = /datum/material_template/cable
	material_total = SHEET_MATERIAL_AMOUNT
	level = 1
	anchored =TRUE
	unacidable = TRUE
	/// Set only while a material overlay owns this cable (engineered
	/// conductors, see power_grid.dm). Everything else asks get_power_region().
	var/datum/material_power_overlay/material_overlay
	/// This piece's entity in the Rust power domain (a cable is not a
	/// `#[vg::component]` -- pure topology data -- so it has no `vg_entity`
	/// of its own; `vg_power_bind_cable` mints and returns one).
	var/power_entity = 0
	name = "power cable"
	desc = "A flexible superconducting cable for heavy-duty power transfer."
	icon = 'icons/obj/power_cond_white.dmi'
	icon_state = "0-1"
	var/d1 = 0
	var/d2 = 1
	plane = PLATING_PLANE
	layer = WIRES_LAYER
	color = COLOR_RED
	var/tmp/obj/machinery/power/breakerbox/breaker_box
	/// Optional registered composite. Ordinary mapped cable retains baseline behavior.
	var/engineered_material_id
	var/material_current = 0

/obj/structure/cable/proc/engineered_material() as /datum/material
	return material_for_role(MATERIAL_ROLE_CONDUCTOR) || (engineered_material_id ? get_material_by_name(engineered_material_id) : null)

/obj/structure/cable/proc/insulation_material() as /datum/material
	return material_for_role(MATERIAL_ROLE_INSULATION)

/obj/structure/cable/proc/set_engineered_material(material_id)
	engineered_material_id = material_id
	if(material_id && !material_build_view(src).overrides)
		apply_material_construction(list(MATERIAL_ROLE_CONDUCTOR = material_id), /datum/material_template/cable, SHEET_MATERIAL_AMOUNT)
	var/datum/material/material = engineered_material()
	if(material?.icon_colour)
		color = material.icon_colour
	power_material_changed()

/obj/structure/cable/material_service_changed()
	. = ..()
	power_material_changed()

/// Engineered conductors put their region on the material overlay.
/obj/structure/cable/proc/power_material_changed()
	if(!engineered_material_id && !material_assembly_view(src).custom)
		return
	SSmachines.power_material_cables[src] = TRUE
	if(power_entity)
		var/datum/material_power_overlay/overlay = SSmachines.power_material_overlays[get_power_region()]
		overlay?.invalidate_material_cache()

/obj/structure/cable/proc/recover_coil(turf/location, length)
	var/obj/item/stack/cable_coil/coil = new(location, length, color, engineered_material_id)
	coil.copy_material_construction_from(src)
	return coil

/obj/structure/cable/drain_power(drain_check, surge, amount = 0)
	if(drain_check)
		return 1

	var/region = get_power_region()
	if(!region)
		return 0

	return power_draw(region, amount, src)

/// The power region this cable is on (asks Rust), or 0.
/obj/structure/cable/proc/get_power_region()
	return power_entity ? (vg_power_region_of(power_entity) || 0) : 0

/// Sends this piece (its turf and directions) to the Rust network. Placing,
/// rotating and moving a cable all call this; Rust works out what it joins.
/obj/structure/cable/proc/power_register()
	var/turf/T = loc
	if(!istype(T))
		power_unregister()
		return
	// A map-load batch binds its cables in one call when it ends (atoms_batch.dm).
	if(SSatoms?.batch_defer(BATCH_WORK_CABLE_BINDS, src))
		return
	SSvg.untrack_entity(src, power_entity)
	power_entity = vg_power_bind_cable(power_entity, power_shape(T))
	power_topology_edited(src)
	SSvg.track_entity(src, power_entity)

/// This piece as `vg_power_bind_cable` takes it: `x, y, z, d1, d2, up, down, link`.
/obj/structure/cable/proc/power_shape(turf/T)
	var/above = 0
	var/below = 0
	if((d1 | d2) & UP)
		var/turf/U = GetAbove(T)
		above = U?.z || 0
	if((d1 | d2) & DOWN)
		var/turf/D = GetBelow(T)
		below = D?.z || 0
	return list(T.x, T.y, T.z, d1, d2, above, below, power_link_id())

/// Binds `cables` (a list, or cable -> TRUE) in one Rust call: a map-load
/// batch's cables (init_and_turfs.md sec 3.3 step 4). Deleted and unplaced
/// pieces are skipped.
/proc/power_bind_cables(list/cables)
	var/list/bound = list()
	var/list/entities = list()
	var/list/shapes = list()
	for(var/obj/structure/cable/C as anything in cables)
		if(QDELETED(C) || !isturf(C.loc))
			continue
		bound += C
		entities += C.power_entity
		shapes += C.power_shape(C.loc)
	if(!length(bound))
		return
	var/list/handles = vg_power_bind_cable_list(entities, shapes)
	power_topology_edited(/obj/structure/cable)
	for(var/i in 1 to length(bound))
		var/obj/structure/cable/C = bound[i]
		SSvg.untrack_entity(C, C.power_entity)
		C.power_entity = handles[i]
		SSvg.track_entity(C, C.power_entity)

/obj/structure/cable/proc/power_unregister()
	SSatoms?.batch_undefer(BATCH_WORK_CABLE_BINDS, src)
	if(!power_entity)
		return
	dq_power_unbind_node(src, power_entity)
	SSvg.untrack_entity(src, power_entity)
	dq_entity_unbind(src, power_entity)
	power_entity = 0

/// Cables with the same non-zero link id connect wherever they are (enders).
/obj/structure/cable/proc/power_link_id()
	return 0

/obj/structure/cable/yellow
	color = COLOR_YELLOW

/obj/structure/cable/green
	color = COLOR_LIME

/obj/structure/cable/blue
	color = COLOR_BLUE

/obj/structure/cable/pink
	color = COLOR_PINK

/obj/structure/cable/orange
	color = COLOR_ORANGE

/obj/structure/cable/cyan
	color = COLOR_CYAN

/obj/structure/cable/white
	color = COLOR_WHITE

REGISTRY_MEMBERSHIP(/obj/structure/cable, REGISTRY_CABLES)

/obj/structure/cable/Initialize(mapload)
	. = ..()

	// ensure d1 & d2 reflect the icon_state for entering and exiting cable

	var/dash = findtext(icon_state, "-")

	d1 = text2num( copytext( icon_state, 1, dash ) )

	d2 = text2num( copytext( icon_state, dash+1 ) )

	var/turf/T = src.loc			// hide if turf is not intact
	if(level==1) hide(!T.is_plating())
	power_register()

/// Phase 1 (unbind): the cable leaves its power region and the material power graph.
/obj/structure/cable/lifecycle_unbind()
	. = ..()
	SSmachines.power_material_cables -= src
	material_overlay?.remove_cable(src) // dirties the overlay's graph; the pair view goes with it
	power_unregister()

/obj/structure/cable/examine(mob/user)
	. = ..()
	if(isobserver(user))
		var/avail = power_avail(get_power_region())
		. += span_warning("[avail > 0 ? "[DisplayPower(avail)] in power network." : "The cable is not powered."]")
	if(engineered_material_id)
		var/datum/material/material = engineered_material()
		. += span_notice("Conductor: [material?.display_name || engineered_material_id], currently [round(material_service_of(src)?.temperature() || T20C, 0.1)] K; [round(material_current, 0.1)] A.")
		if(material?.critical_temperature)
			. += span_notice("Superconducting envelope: below [round(material.critical_temperature, 0.1)] K and [round(material.critical_current_density)] relative current density.")

// Rotating cables requires d1 and d2 to be rotated
/obj/structure/cable/set_dir(new_dir)
	. = ..()

	// If d1 is 0, then it's a not, and doesn't rotate
	if(d1)
		// Using turn will maintain the cable's shape
		// Taking the difference between current orientation and new one
		d1 = turn(d1, dir2angle(new_dir) - dir2angle(dir))
	d2 = turn(d2, dir2angle(new_dir) - dir2angle(dir))

	// Maintain d1 < d2
	if(d1 > d2)
		var/temp = d1
		d1 = d2
		d2 = temp

	//	..()	Cable sprite generation is dependent upon only d1 and d2.
	// 			Actually changing dir will rotate the generated sprite to look wrong, but function correctly.
	update_icon()
	if(flags & ATOM_INITIALIZED)
		power_register()

/obj/structure/cable/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(flags & ATOM_INITIALIZED)
		power_register()

///////////////////////////////////
// General procedures
///////////////////////////////////

//If underfloor, hide the cable
/obj/structure/cable/hide(i)
	if(istype(loc, /turf))
		invisibility = i ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
	update_icon()

/obj/structure/cable/hides_under_flooring()
	return 1

DECLARE_APPEARANCE_PROC(/obj/structure/cable, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/cable/appearance_overlays()
	. = list()
	// We rely on the icon state for the wire Initialize(), prevent any updates to the icon before init passed
	if(!(flags & ATOM_INITIALIZED))
		return .
	icon_state = "[d1]-[d2]"
	alpha = invisibility ? 127 : 255

// Items usable on a cable :
//   - Wirecutters : cut it duh !
//   - Cable coil : merge cables
//   - Multitool : get the power currently passing through the cable
//

DECLARE_INTERACTIONS(/obj/structure/cable, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/cable/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/turf/T = src.loc
	if(!T.is_plating())
		return INTERACTION_HANDLED_PASS
	if(istype(W, /obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/coil = W
		if(coil.get_amount() < 1)
			to_chat(user, "Not enough cable")
			return INTERACTION_HANDLED_PASS
		coil.cable_join(src, user)
	else if(!(W.flags & NOCONDUCT))
		shock(user, 50, 0.7)
	add_fingerprint(user)
	return INTERACTION_HANDLED_PASS

/obj/structure/cable/wirecutter_act(mob/user, obj/item/W)
	var/turf/T = src.loc
	if(!T.is_plating())
		return ITEM_INTERACT_BLOCKING

	var/obj/item/stack/cable_coil/CC
	if(d1 == UP || d2 == UP)
		to_chat(user, span_warning("You must cut this cable from above."))
		return ITEM_INTERACT_BLOCKING

	if(breaker_box())
		to_chat(user, span_warning("This cable is connected to nearby breaker box. Use breaker box to interact with it."))
		return ITEM_INTERACT_BLOCKING

	if(shock(user, 50))
		return ITEM_INTERACT_BLOCKING

	if(src.d1)	// 0-X cables are 1 unit, X-X cables are 2 units long
		CC = recover_coil(T, 2)
	else
		CC = recover_coil(T, 1)

	src.add_fingerprint(user)
	src.transfer_fingerprints_to(CC)

	for(var/mob/O in viewers(src, null))
		O.show_message(span_warning("[user] cuts the cable."), 1)

	if(d1 == DOWN || d2 == DOWN)
		var/turf/turf = GetBelow(src)
		if(turf)
			for(var/obj/structure/cable/c in turf_contents_of_type(turf, /obj/structure/cable))
				if(c.d1 == UP || c.d2 == UP)
					destroyed(c, user)

	investigate_log("was cut by [key_name(user, user.client)] in [user.loc.loc]","wires")

	destroyed(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/structure/cable/multitool_act(mob/user, obj/item/W)
	var/turf/T = src.loc
	if(!T.is_plating())
		return ITEM_INTERACT_BLOCKING
	var/avail = power_avail(get_power_region())
	if(avail > 0)
		to_chat(user, span_warning("[DisplayPower(avail)] in power network."))
	else
		to_chat(user, span_warning("The cable is not powered."))
	shock(user, 5, 0.2)
	add_fingerprint(user)
	return ITEM_INTERACT_SUCCESS

// shock the user with probability prb
/obj/structure/cable/proc/shock(mob/user, prb, siemens_coeff = 1.0)
	if(!prob(prb))
		return 0
	if (electrocute_mob(user, src, src, siemens_coeff))
		fx_sparks(src, 5)
		if(user.has_status(STAT_STUNNED))
			return 1
	return 0

//explosion handling
/// Blasted cables leave a length of coil behind.
/obj/structure/cable/atom_destruction(damage_flag)
	if(damage_flag == BOMB)
		recover_coil(loc, d1 ? 2 : 1)
	return ..()

/obj/structure/cable/proc/cableColor(colorC)
	var/color_n = "#DD0000"
	if(colorC)
		color_n = colorC
	color = color_n

//////////////////////////////////////////////
// Powernets handling helpers
//////////////////////////////////////////////

//if powernetless_only = 1, will only get connections without powernet
/obj/structure/cable/proc/get_connections(powernetless_only = 0)
	. = list()	// this will be a list of all connected power objects
	var/turf/T

	// Handle standard cables in adjacent turfs
	for(var/cable_dir in list(d1, d2))
		if(cable_dir == 0)
			continue
		var/reverse = GLOB.reverse_dir[cable_dir]
		T = get_zstep(src, cable_dir)
		if(T)
			for(var/obj/structure/cable/C in contents_of(T))
				if(C.d1 == reverse || C.d2 == reverse)
					. += C
		if(cable_dir & (cable_dir - 1)) // Diagonal, check for /\/\/\ style cables along GLOB.cardinal directions
			for(var/pair in list(NORTH|SOUTH, EAST|WEST))
				T = get_step(src, cable_dir & pair)
				if(T)
					var/req_dir = cable_dir ^ pair
					for(var/obj/structure/cable/C in contents_of(T))
						if(C.d1 == req_dir || C.d2 == req_dir)
							. += C

	// Handle cables on the same turf as us
	for(var/obj/structure/cable/C in contents_of(loc))
		if(C.d1 == d1 || C.d2 == d1 || C.d1 == d2 || C.d2 == d2) // if either of C's d1 and d2 match either of ours
			. += C

	if(d1 == 0)
		for(var/obj/machinery/power/P in contents_of(loc))
			if(!powernetless_only || !P.power_region)
				. += P

	// if the caller asked for powernetless cables only, dump the ones with powernets
	if(powernetless_only)
		for(var/obj/structure/cable/C in .)
			if(C.material_overlay)
				. -= C

///////////////////////////////////////////////
// The cable coil object, used for laying cable
///////////////////////////////////////////////

////////////////////////////////
// Definitions
////////////////////////////////

#define MAXCOIL 30

/obj/item/stack/cable_coil
	material_template = /datum/material_template/cable
	material_total = SHEET_MATERIAL_AMOUNT
	name = "cable coil"
	icon = 'icons/obj/power.dmi'
	icon_state = "coil"
	amount = MAXCOIL
	max_amount = MAXCOIL
	color = COLOR_RED
	gender = NEUTER
	desc = "A coil of power cable."
	throwforce = 10
	w_class = ITEMSIZE_SMALL
	throw_speed = 2
	throw_range = 5
	slot_flags = SLOT_BELT
	item_state = "coil"
	attack_verb = list("whipped", "lashed", "disciplined", "flogged")
	stacktype = /obj/item/stack/cable_coil
	singular_name = "length"
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY
	tool_qualities = list(TOOL_CABLE_COIL)
	singular_name = "cable"

/// The engineered material a coil is made of (its constructor param).
/obj/item/stack/cable_coil/var/material_id

/// A coil is made full unless its first argument (the stack's amount param) says otherwise.
/obj/item/stack/cable_coil
	amount_at_make = MAXCOIL

// ALLOW(init/INSTANCE_STATE): a coil takes its blueprint's effects and its engineered material's name
/obj/item/stack/cable_coil/Initialize(mapload)
	. = ..()
	apply_blueprint_effects()
	material_engineered_id_set(src, material_id)
	update_icon()
	update_wclass()
	if(material_engineered_id(src))
		var/datum/material/material = get_material_by_name(material_engineered_id(src))
		name = "[material?.display_name || "engineered"] cable coil"
		desc = "A layered power conductor. Its core carries current while its functional layer and jacket govern thermal stability."

/obj/item/stack/cable_coil/examine(mob/user)
	. = ..()
	var/engineered_id = material_engineered_id(src)
	if(engineered_id)
		var/datum/material/material = get_material_by_name(engineered_id)
		. += span_notice("Conductor construction: [material?.display_name || engineered_id].")

///////////////////////////////////
// General procedures
///////////////////////////////////

//you can use wires to heal robotics
/obj/item/stack/cable_coil/attack(mob/living/A, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(ishuman(A) && stance == I_HELP)
		var/mob/living/carbon/human/H = A
		var/obj/item/organ/external/S = H.organs_by_name[user.zone_sel.selecting]

		if(!S || !S.is_robotic() || S.open == 3)
			return ..()

		// No welding nanoform limbs
		if(S.robotic > ORGAN_LIFELIKE)
			return ..()

		if(S.organ_tag == BP_HEAD)
			if(H.get_equipped_item(SLOT_ID_HEAD) && istype(H.get_equipped_item(SLOT_ID_HEAD),/obj/item/clothing/head/helmet/space))
				to_chat(user, span_warning("You can't apply [src] through [H.get_equipped_item(SLOT_ID_HEAD)]!"))
				return ITEM_INTERACT_FAILURE
		else
			if(H.get_equipped_item(SLOT_ID_SUIT) && istype(H.get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
				to_chat(user, span_warning("You can't apply [src] through [H.get_equipped_item(SLOT_ID_SUIT)]!"))
				return ITEM_INTERACT_FAILURE

		var/use_amt = min(src.amount, CEILING(S.get_burn()/5, 1), 5)
		if(can_use(use_amt))
			if(S.robo_repair(5*use_amt, BURN, "some damaged wiring", src, user, PROC_REF(robo_repair_used), list(use_amt)))
				return ITEM_INTERACT_SUCCESS
		return ITEM_INTERACT_FAILURE

	else
		return ..()

/// A robotic limb repair with this coil finished.
/obj/item/stack/cable_coil/proc/robo_repair_used(mob/living/user, use_amt)
	use(use_amt)

/// One or two lengths show as a piece, more as a coil.
/obj/item/stack/cable_coil/look_state()
	if(amount == 1)
		return "coil1"
	if(amount == 2)
		return "coil2"
	return "coil"

/// A piece of cable is named so, a coil keeps its own name.
/obj/item/stack/cable_coil/proc/update_coil_name()
	if(amount == 1 || amount == 2)
		name = "cable piece"
	else
		name = initial(name)

/obj/item/stack/cable_coil/set_amount(new_amount, no_limits = FALSE)
	. = ..()
	if(!QDELETED(src))
		update_coil_name()

/obj/item/stack/cable_coil/proc/set_cable_color(selected_color, user)
	if(!selected_color)
		return

	var/final_color = GLOB.possible_cable_coil_colours[selected_color]
	if(!final_color)
		final_color = GLOB.possible_cable_coil_colours["Red"]
		selected_color = "red"
	color = final_color
	to_chat(user, span_notice("You change \the [src]'s color to [lowertext(selected_color)]."))

/obj/item/stack/cable_coil/proc/update_wclass()
	if(amount == 1)
		w_class = ITEMSIZE_TINY
	else
		w_class = ITEMSIZE_SMALL

/obj/item/stack/cable_coil/multitool_act(mob/user, obj/item/W)
	var/selected_type = rerun_ask(user, "k530", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/choice, message = "Pick new colour.", title = "Cable Colour", choices = GLOB.possible_cable_coil_colours)
	if(isnull(selected_type))
		return ITEM_INTERACT_BLOCKING
	set_cable_color(selected_type, user)
	return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/stack/cable_coil)
	op("cable_coil_make_restraint", menu(), label("Make Cable Restraints"), needs(carried()), then(PROC_REF(cable_coil_make_restraint)))
	param(nameof(color), pos = 2)
	param(nameof(material_id), pos = 3)
	rolls(nameof(color), pick_one(list(COLOR_RED, COLOR_BLUE, COLOR_LIME, COLOR_ORANGE, COLOR_WHITE, COLOR_PINK, COLOR_YELLOW, COLOR_CYAN)), when = cond_not(nameof(color)))
	rolls(ROLL_PIXEL, PIXEL_JITTER(2))

/// Old verb "Make Cable Restraints" (an obj verb with no `set src`, so src in usr).
/obj/item/stack/cable_coil/proc/cable_coil_make_restraint(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/M = user

	if(ishuman(M) && !M.restrained() && !M.stat && !M.has_status(STAT_PARALYZED) && ! M.has_status(STAT_STUNNED))
		if(!istype(M.loc,/turf)) return
		if(src.amount <= 14)
			to_chat(M, span_warning("You need at least 15 lengths to make restraints!"))
			return
		var/obj/item/handcuffs/cable/B = new /obj/item/handcuffs/cable(M.loc)
		B.color = color
		to_chat(M, span_notice("You wind some cable together to make some restraints."))
		src.use(15)
	else
		to_chat(M, span_notice("You cannot do that."))

// Items usable on a cable coil :
//   - Wirecutters : cut them duh !
//   - Cable coil : merge cables

/obj/item/stack/cable_coil/transfer_to(obj/item/stack/cable_coil/S)
	if(!istype(S))
		return
	if(material_engineered_id(src) != material_engineered_id(S))
		return
	..()

/obj/item/stack/cable_coil/use()
	. = ..()
	update_icon()
	return

/obj/item/stack/cable_coil/add()
	. = ..()
	update_icon()
	return

///////////////////////////////////////////////
// Cable laying procedures
//////////////////////////////////////////////

// called when cable_coil is clicked on a turf/simulated/floor
/obj/item/stack/cable_coil/proc/turf_place(turf/simulated/F, mob/user)
	if(!isturf(user.loc))
		return

	if(get_amount() < 1) // Out of cable
		to_chat(user, "There is no cable left.")
		return

	if(get_dist(F,user) > 1) // Too far
		to_chat(user, "You can't lay cable at a place that far away.")
		return

	if(!F.is_plating())		// Ff floor is intact, complain
		to_chat(user, "You can't lay cable there unless the floor tiles are removed.")
		return

	var/dirn
	if(user.loc == F)
		dirn = user.dir			// if laying on the tile we're on, lay in the direction we're facing
	else
		dirn = get_dir(F, user)

	var/end_dir = 0
	if(istype(F, /turf/simulated/open))
		if(!can_use(2))
			to_chat(user, "You don't have enough cable to do this!")
			return
		end_dir = DOWN

	for(var/obj/structure/cable/LC in turf_contents_of_type(F, /obj/structure/cable))
		if((LC.d1 == dirn && LC.d2 == end_dir ) || ( LC.d2 == dirn && LC.d1 == end_dir))
			to_chat(user, span_warning("There's already a cable at that position."))
			return

	put_cable(F, user, end_dir, dirn)
	if(end_dir == DOWN)
		put_cable(GetBelow(F), user, UP, 0)
		to_chat(user, "You slide some cable downward.")

/obj/item/stack/cable_coil/proc/put_cable(turf/simulated/F, mob/user, d1, d2)
	if(!istype(F))
		return

	var/obj/structure/cable/C
	if(istype(src,/obj/item/stack/cable_coil/heavyduty)) // this is the only cable that does this, not worth an override
		C = new /obj/structure/cable/heavyduty(F)
	else
		C = new /obj/structure/cable(F)
	C.set_engineered_material(material_engineered_id(src))
	C.copy_material_construction_from(src)
	C.cableColor(color)
	C.d1 = d1
	C.d2 = d2
	C.add_fingerprint(user)
	C.update_icon()
	C.power_register()

	use(1)
	if (C.shock(user, 50))
		if (prob(50)) //fail
			C.recover_coil(C.loc, 1)
			spent(C, user)

// called when cable_coil is click on an installed obj/cable
// or click on a turf that already contains a "node" cable
/obj/item/stack/cable_coil/proc/cable_join(obj/structure/cable/C, mob/user)
	if(C.engineered_material_id && C.engineered_material_id != material_engineered_id(src))
		to_chat(user, span_warning("The two conductor constructions cannot be spliced without a transition terminal."))
		return
	var/turf/U = user.loc
	if(!isturf(U))
		return

	var/turf/T = C.loc

	if(!isturf(T) || !T.is_plating())		// sanity checks, also stop use interacting with T-scanner revealed cable
		return

	if(get_dist(C, user) > 1)		// make sure it's close enough
		to_chat(user, "You can't lay cable at a place that far away.")
		return

	if(U == T) //if clicked on the turf we're standing on, try to put a cable in the direction we're facing
		turf_place(T,user)
		return

	var/dirn = get_dir(C, user)

	// one end of the clicked cable is pointing towards us
	if(C.d1 == dirn || C.d2 == dirn)
		if(!U.is_plating())						// can't place a cable if the floor is complete
			to_chat(user, "You can't lay cable there unless the floor tiles are removed.")
			return
		else
			// cable is pointing at us, we're standing on an open tile
			// so create a stub pointing at the clicked cable on our tile

			var/fdirn = turn(dirn, 180)		// the opposite direction

			for(var/obj/structure/cable/LC in turf_contents_of_type(U, /obj/structure/cable))		// check to make sure there's not a cable there already
				if(LC.d1 == fdirn || LC.d2 == fdirn)
					to_chat(user, "There's already a cable at that position.")
					return
			put_cable(U,user,0,fdirn)
			return

	// exisiting cable doesn't point at our position, so see if it's a stub
	else if(C.d1 == 0)
							// if so, make it a full cable pointing from it's old direction to our dirn
		var/nd1 = C.d2	// these will be the new directions
		var/nd2 = dirn

		if(nd1 > nd2)		// swap directions to match icons/states
			nd1 = dirn
			nd2 = C.d2


		for(var/obj/structure/cable/LC in turf_contents_of_type(T, /obj/structure/cable))		// check to make sure there's no matching cable
			if(LC == C)			// skip the cable we're interacting with
				continue
			if((LC.d1 == nd1 && LC.d2 == nd2) || (LC.d1 == nd2 && LC.d2 == nd1) )	// make sure no cable matches either direction
				to_chat(user, "There's already a cable at that position.")
				return

		C.cableColor(color)
		C.set_engineered_material(material_engineered_id(src))
		C.copy_material_construction_from(src)

		C.d1 = nd1
		C.d2 = nd2

		C.add_fingerprint()
		C.update_icon()
		C.power_register()

		use(1)

		if (C.shock(user, 50))
			if (prob(50)) //fail
				C.recover_coil(C.loc, 2)
				spent(C, user)
				return
		return

//////////////////////////////
// Misc.
/////////////////////////////

/obj/item/stack/cable_coil/cut
	item_state = "coil2"

/obj/item/stack/cable_coil/cut/Initialize(mapload)
	. = ..()
	set_amount(rand(1,2), TRUE)
	pixel_x = rand(-2,2)
	pixel_y = rand(-2,2)
	update_icon()
	update_wclass()

/obj/item/stack/cable_coil/yellow
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_YELLOW

/obj/item/stack/cable_coil/blue
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_BLUE

/obj/item/stack/cable_coil/green
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_LIME

/obj/item/stack/cable_coil/pink
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_PINK

/obj/item/stack/cable_coil/orange
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_ORANGE

/obj/item/stack/cable_coil/cyan
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_CYAN

/obj/item/stack/cable_coil/white
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_WHITE

/obj/item/stack/cable_coil/silver
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_SILVER

/obj/item/stack/cable_coil/gray
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_GRAY

/obj/item/stack/cable_coil/black
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_BLACK

/obj/item/stack/cable_coil/maroon
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_MAROON

/obj/item/stack/cable_coil/olive
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_OLIVE

/obj/item/stack/cable_coil/lime
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_LIME

/obj/item/stack/cable_coil/teal
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_TEAL

/obj/item/stack/cable_coil/navy
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_NAVY

/obj/item/stack/cable_coil/purple
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_PURPLE

/obj/item/stack/cable_coil/beige
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_BEIGE

/obj/item/stack/cable_coil/brown
	stacktype = /obj/item/stack/cable_coil
	color = COLOR_BROWN

/obj/item/stack/cable_coil/random/Initialize(mapload)
	stacktype = /obj/item/stack/cable_coil
	color = pick(COLOR_RED, COLOR_BLUE, COLOR_LIME, COLOR_WHITE, COLOR_PINK, COLOR_YELLOW, COLOR_CYAN, COLOR_SILVER, COLOR_GRAY, COLOR_BLACK, COLOR_MAROON, COLOR_OLIVE, COLOR_LIME, COLOR_TEAL, COLOR_NAVY, COLOR_PURPLE, COLOR_BEIGE, COLOR_BROWN)
	. = ..()

/obj/item/stack/cable_coil/random_belt/Initialize(mapload)
	stacktype = /obj/item/stack/cable_coil
	color = pick(COLOR_RED, COLOR_YELLOW, COLOR_ORANGE)
	. = ..()

//Endless alien cable coil

/datum/category_item/catalogue/anomalous/precursor_a/alien_wire
	name = "Precursor Alpha Object - Recursive Spool"
	desc = "Upon visual inspection, this merely appears to be a \
	spool for silver-colored cable. If one were to use this for \
	some time, however, it would become apparent that the cables \
	inside the spool appear to coil around the spool endlessly, \
	suggesting an infinite length of wire.\
	<br><br>\
	In reality, an infinite amount of something within a finite space \
	would likely not be able to exist. Instead, the spool likely has \
	some method of creating new wire as it is unspooled. How this is \
	accomplished without an apparent source of material would require \
	further study."
	value = CATALOGUER_REWARD_EASY

/obj/item/stack/cable_coil/alien
	name = "alien spool"
	desc = "A spool of cable. No matter how hard you try, you can never seem to get to the end."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_wire)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "coil"
	amount = MAXCOIL
	max_amount = MAXCOIL
	color = COLOR_SILVER
	throwforce = 10
	w_class = ITEMSIZE_SMALL
	throw_speed = 2
	throw_range = 5
	slot_flags = SLOT_BELT
	attack_verb = list("whipped", "lashed", "disciplined", "flogged")
	stacktype = null
	toolspeed = 0.25

/obj/item/stack/cable_coil/alien/Initialize(mapload, length = MAXCOIL, param_color = null)		//There has to be a better way to do this.
	. = ..()
	if(embed_chance == -1)		//From /obj/item, don't want to do what the normal cable_coil does
		if(sharp)
			embed_chance = force/w_class
		else
			embed_chance = force/(w_class*3)
	update_icon()

/// An alien spool always shows its own state.
/obj/item/stack/cable_coil/alien/look_state()
	return initial(icon_state)

/obj/item/stack/cable_coil/alien/can_use(used)
	return 1

/obj/item/stack/cable_coil/alien/use()	//It's endless
	return 1

/obj/item/stack/cable_coil/alien/add()	//Still endless
	return 0

/obj/item/stack/cable_coil/alien/update_wclass()
	return 0

/obj/item/stack/cable_coil/alien/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		. += "It doesn't seem to have a beginning, or an end."

// The endless coil's touch replaces the stack's split: it asks how much wire to take.
CAPABILITIES(/obj/item/stack/cable_coil/alien)
	op("split", hand(), ungated(), label("Take wire"), then(PROC_REF(alien_coil_hand)))

/// Old attack_hand: take wire from the endless coil in the other hand; otherwise fall through to pickup.
/obj/item/stack/cable_coil/alien/proc/alien_coil_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (user.get_inactive_hand() != src)
		return OP_DECLINE
	open_request(src, /datum/prompt/number, PROC_REF(alien_wire_taken), answerer = user, title = "Split stacks", question = "How many units of wire do you want to take from [src]? You can only take up to [amount] at a time.", default = 1, max_value = amount, min_value = 1, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return OP_OK

/// The answered length of wire comes off into the hand.
/obj/item/stack/cable_coil/alien/proc/alien_wire_taken(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/N = A.answer.value
	if(N)
		if(N && N <= amount)
			var/obj/item/stack/cable_coil/CC = new/obj/item/stack/cable_coil(user.loc)
			CC.set_amount(N, TRUE)
			CC.update_icon()
			to_chat(user,span_blue("You take [N] units of wire from the [src]."))
			if (CC)
				user.put_in_hands(CC)
				src.add_fingerprint(user)
				CC.add_fingerprint(user)
				if (src && user.check_current_machine(src))
					src.interact(user)

#undef MAXCOIL

/// A cable is a member of its material overlay's cables (two-sided); deleting it leaves the list.
/obj/structure/cable/relations()
	. = ..()
	. += rel_one(nameof(material_overlay), back = nameof(/datum/material_power_overlay::cables))
/datum/material_power_overlay/relations()
	. = ..()
	. += rel_many(nameof(cables), back = nameof(/obj/structure/cable::material_overlay))

/// The breaker box this cable belongs to: a relation view, null once that box is deleted.
/obj/structure/cable/proc/breaker_box() as /obj/machinery/power/breakerbox
	return breaker_box
