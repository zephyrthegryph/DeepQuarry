/turf/simulated/wall
	name = "wall"
	desc = "A huge chunk of metal used to separate rooms."
	icon = 'icons/turf/wall_masks.dmi'
	icon_state = "generic"
	opacity = 1
	density = TRUE
	blocks_air = 1
	thermal_conductivity = WALL_HEAT_TRANSFER_COEFFICIENT
	heat_capacity = 312500 //a little over 5 cm thick , 312500 for 1 m by 2.5 m by 0.25 m plasteel wall

	var/wall_masks = 'icons/turf/wall_masks.dmi'
	// Walls use integrity (damage.md §5): max_integrity is the material cap,
	// set by update_material().
	uses_integrity = TRUE
	max_integrity = 150
	var/global/damage_overlays[16]
	var/active
	var/can_open = 0
	var/datum/material/girder_material
	var/datum/material/material
	var/datum/material/reinf_material
	var/last_state
	var/construction_stage

	/// Corner states from dirs_to_corner_states(), interned with string_list() so walls with the
	/// same shape share one list. Null until update_connections(); read it via get_wall_connections().
	var/list/wall_connections
	rad_insulation = RAD_MEDIUM_INSULATION

// Walls always hide the stuff below them.
/turf/simulated/wall/levelupdate()
	for(var/obj/O in turf_contents_of_type(src, /obj))
		O.hide(1)

TYPE_TABLE_DECLARE(/turf/simulated/wall, wall_forced_materials, null)

CAPABILITIES(/turf/simulated/wall)
	every(2 SECONDS, then(PROC_REF(wall_step)), when = nameof(radioactive))
	op("wall_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 2), then(PROC_REF(wall_item)))
	wall_construction()
	op("wall_dissolve", ai(), wait(5 SECONDS), then(PROC_REF(wall_dissolve_done)))
	op("wall_touch", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Touch"), then(PROC_REF(wall_hand)))
	op("wall_graffiti", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Graffiti"), then(PROC_REF(wall_graffiti_alt)))
	adjacency(ADJ_KIND_SMOOTH, dirs = ADJ_ALL_AROUND, connects = PROC_REF(smooth_joins), changed = PROC_REF(smooth_changed))
	on_change(nameof(material), ANY, then(PROC_REF(smooth_inputs_changed)))
	on_change(nameof(density), ANY, then(PROC_REF(edge_inputs_changed)))
	param(nameof(wall_material_key), pos = 1)
	param(nameof(reinf_material_key), pos = 2)
	param(nameof(girder_material_key), pos = 3)

/// The resin wall porous under a hivenode touch (resin.dm) dissolves once the toucher has stayed five seconds.
/turf/simulated/wall/proc/wall_dissolve_done(datum/act/op/A)
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	dismantle_wall()

/// The wall's material, reinforcement and girder (its constructor params; the type's forced ones win).
/turf/simulated/wall/var/wall_material_key
/turf/simulated/wall/var/reinf_material_key
/turf/simulated/wall/var/girder_material_key

// ALLOW(init/INSTANCE_STATE): a wall takes its materials (the type's forced ones first), girder and radioactivity
/turf/simulated/wall/Initialize(mapload)
	var/list/forced_materials = TYPE_TABLE_GET(src, wall_forced_materials)
	if(forced_materials)
		wall_material_key = forced_materials[1]
		reinf_material_key = length(forced_materials) >= 2 ? forced_materials[2] : null
		girder_material_key = length(forced_materials) >= 3 ? forced_materials[3] : null
	. = ..()
	icon_state = "blank"
	if(!damage_overlays[1]) //list hasn't been populated
		generate_overlays()
	set_material(get_material_by_name(wall_material_key || DEFAULT_WALL_MATERIAL))
	girder_material = get_material_by_name(girder_material_key || DEFAULT_WALL_MATERIAL)
	if(!isnull(reinf_material_key))
		set_reinf_material(get_material_by_name(reinf_material_key))
	update_material()
	check_radioactive()

/// TRUE while one of its materials is radioactive.
/turf/simulated/wall/var/radioactive = FALSE
TRACKED(/turf/simulated/wall, radioactive)
/// TRUE while the wall carries a thermite coating (draws it; lighting it melts the wall).
/turf/simulated/wall/var/thermite = FALSE
TRACKED(/turf/simulated/wall, thermite)

/// Call after its materials change.
/turf/simulated/wall/proc/check_radioactive()
	set_radioactive(wall_radioactivity() ? TRUE : FALSE)

/turf/simulated/wall/proc/wall_radioactivity()
	return dq_material_radioactivity(material) + (reinf_material ? dq_material_radioactivity(reinf_material) / 2 : 0) + (girder_material ? dq_material_radioactivity(girder_material) / 2 : 0)

/turf/simulated/wall/examine_icon()
	return icon(icon=initial(icon), icon_state=initial(icon_state))

/// A wall radiates only while one of its materials is radioactive (every(), parked otherwise: walls are numerous).
/turf/simulated/wall/proc/wall_step(datum/act/timer/A)
	if(!radiate())
		set_radioactive(FALSE)

/turf/simulated/wall/proc/get_material()
	return material

/turf/simulated/wall/bullet_act(obj/item/projectile/Proj)
	if(istype(Proj,/obj/item/projectile/beam))
		burn(2500)
	else if(istype(Proj,/obj/item/projectile/ion))
		burn(500)

	var/proj_damage = Proj.get_structure_damage()

	if(Proj.obj_damage_type() == BURN && proj_damage > 0)
		if(thermite)
			thermitemelt()

	// A reflective wall catches only its share of a beam and bounces the rest.
	var/reflectivity = 0
	if(istype(Proj,/obj/item/projectile/beam) && material && material.reflectivity >= 0.5) // Time to reflect lasers.
		reflectivity = material.reflectivity

	projectile_damage(Proj, null, reflectivity || 1)

	if(reflectivity)
		Proj.damage = min(proj_damage, 100) * (1 - reflectivity)

		visible_message(span_danger("\The [src] reflects \the [Proj]!"))

		// Find a turf near or on the original location to bounce to
		var/new_x = Proj.starting.x + pick(0, 0, 0, -1, 1, -2, 2)
		var/new_y = Proj.starting.y + pick(0, 0, 0, -1, 1, -2, 2)
		var/turf/curloc = get_step(src, get_dir(src, Proj.starting))

		Proj.penetrating += 1 // Needed for the beam to get out of the wall.

		// redirect the projectile
		Proj.redirect(new_x, new_y, curloc, null)

/// Projectile adapter. The share of a round a wall catches is capped at 100,
/// so that things like emitters can't destroy walls in one hit.
/turf/simulated/wall/projectile_damage(obj/item/projectile/P, def_zone, multiplier = 1)
	var/structure_damage = P.get_structure_damage()
	if(structure_damage > 100)
		multiplier *= 100 / structure_damage
	return receive_projectile(P, def_zone, multiplier)

/turf/simulated/wall/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	..()
	thrown_damage(source, throwingdatum)

/// Thrown-impact adapter: mobs bounce off, and light throws don't mark the wall.
/turf/simulated/wall/thrown_damage(atom/movable/source, datum/thrownthing/throwingdatum)
	if(ismob(source) || source.thrown_impact_force(throwingdatum) < 15)
		return 0
	return ..()

/turf/simulated/wall/proc/clear_plants()
	for(var/obj/effect/overlay/wallrot/WR in turf_contents_of_type(src, /obj/effect/overlay/wallrot))
		dissolved(WR)
	for(var/obj/effect/plant/plant in range(src, 1))
		if(!plant.floor) //shrooms drop to the floor
			plant.set_floor(1)
			plant.pixel_x = 0
			plant.pixel_y = 0
		plant.update_neighbors()

/turf/simulated/wall/ChangeTurf(turf/N, tell_universe, force_lighting_update, preserve_outdoors)
	clear_plants()
	. = ..(N, tell_universe, force_lighting_update, preserve_outdoors)

//Appearance
/turf/simulated/wall/examine(mob/user)
	. = ..()

	var/band = dq_damage_band_for(src)
	if(band)
		. += damage_flavour_text(band)

	if(locate_on(src, /obj/effect/overlay/wallrot))
		. += span_warning("There is fungus growing on [src].")

//Damage

/turf/simulated/wall/melt()

	if(!can_melt())
		return

	src.ChangeTurf(/turf/simulated/floor/plating)

	var/turf/simulated/floor/F = src
	if(!F)
		return
	F.burn_tile()
	F.set_scorch_state("wall_thermite")
	visible_message(span_danger("\The [src] spontaneously combusts!.")) //!!OH SHIT!!
	return

/// Missing integrity as a fraction of the material cap (0 = intact).
/turf/simulated/wall/proc/wall_damage_fraction()
	if(max_integrity <= 0)
		return 0
	return (max_integrity - get_integrity()) / max_integrity

/// The material cap: plating plus reinforcement.
/turf/simulated/wall/proc/material_integrity_cap()
	. = material?.integrity || 0
	if(reinf_material)
		. += reinf_material.integrity
	return max(1, .)

/// Wall-rot leaves a tenth of the wall: every hit on a rotting wall counts ten times.
/turf/simulated/wall/run_atom_armor(damage_amount, damage_type, damage_flag = 0, attack_dir, armour_penetration = 0)
	. = ..()
	if(. > 0 && (locate_on(src, /obj/effect/overlay/wallrot)))
		. *= 10

/turf/simulated/wall/on_update_integrity(old_value, new_value)
	. = ..()
	sync_damage_step()

/turf/simulated/wall/atom_destruction(damage_flag)
	. = ..()
	dismantle_wall()


/turf/simulated/wall/proc/dismantle_wall(devastated, explode, no_product)
	// A wall built from a substance material discharges its effect when breached.

	play_sfx(src, SFX_ITEMS_WELDER)
	if(!no_product)
		if(reinf_material)
			reinf_material.place_dismantled_girder(src, reinf_material, girder_material)
		else
			material.place_dismantled_girder(src, null, girder_material)
		if(!devastated)
			if (reinf_material)
				material.place_dismantled_product(src)
			else
				material.place_dismantled_product(src, 2)

	for(var/obj/O in turf_contents_of_type(src, /obj)) //Eject contents!
		if(istype(O,/obj/structure/sign/poster))
			var/obj/structure/sign/poster/P = O
			P.roll_and_drop(src)
		else
			O.forceMove(src)

	clear_plants()
	set_material(get_material_by_name("placeholder"))
	set_reinf_material(null)
	girder_material = null
	update_connections(1)

	ChangeTurf(/turf/simulated/floor/plating)

/// Walls take blast on their own ladder, not a fraction of max integrity, so a
/// heavy blast still breaches ordinary walls. The epicentre obliterates
/// outright; a strong girder may survive it.
/turf/simulated/wall/receive_explosion(severity)
	if(resistance_flags & BOMB_PROOF)
		return 0
	if(react_to_entry(DAMAGE_ENTRY_EXPLOSION, severity)) // the ladder below is not a DAMAGE_ENTRY_EXPLOSION packet
		return 0
	switch(round(severity))
		if(1)
			if(girder_material.explosion_resistance >= 25 && prob(girder_material.explosion_resistance))
				new /obj/structure/girder/displaced(src, girder_material.name)
			ChangeTurf(get_base_turf_by_area(src))
			return max_integrity
		if(2)
			if(prob(25))
				dismantle_wall(1, 1)
				return max_integrity
			return deal_damage(DAMAGE_BLAST, rand(150, 250), flags = DAMAGE_PACKET_SILENT)
		if(3)
			return deal_damage(DAMAGE_BLAST, rand(0, 250), flags = DAMAGE_PACKET_SILENT)
	return 0

// Wall-rot effect, a nasty fungus that destroys walls.
/turf/simulated/wall/proc/rot()
	if(locate_on(src, /obj/effect/overlay/wallrot))
		return FALSE

	// Wall-rot can't go onto walls that are surrounded in all four GLOB.cardinal directions.
	// Because of spores, or something. It's actually to avoid the pain that is removing wallrot surrounded by
	// four r-walls.
	var/at_least_one_open_turf = FALSE
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		if(!T.check_density())
			at_least_one_open_turf = TRUE
			break

	if(!at_least_one_open_turf)
		return FALSE

	var/number_rots = rand(2,3)
	for(var/i=0, i<number_rots, i++)
		new/obj/effect/overlay/wallrot(src)
	return TRUE

/turf/simulated/wall/proc/can_melt()
	if(material.flags & MATERIAL_UNMELTABLE)
		return 0
	return 1

/turf/simulated/wall/proc/thermitemelt(mob/user as mob)
	if(!can_melt())
		return
	var/obj/effect/overlay/O = new/obj/effect/overlay( src )
	O.name = "Thermite"
	O.desc = "Looks hot."
	O.icon = 'icons/effects/fire.dmi'
	O.icon_state = "2"
	O.set_anchored(TRUE)
	O.set_density(TRUE)
	O.plane = ABOVE_PLANE

	if(girder_material.integrity >= 150 && !girder_material.is_brittle()) //Strong girders will remain in place when a wall is melted.
		dismantle_wall(1,1)
	else
		src.ChangeTurf(/turf/simulated/floor/plating)

	var/turf/simulated/floor/F = src
	F.burn_tile()
	F.icon_state = "dmg[rand(1,4)]"
	to_chat(user, span_warning("The thermite starts melting through the wall."))

	after(null, 10 SECONDS, GLOBAL_PROC_REF(thermite_cleanup), with = list(O)) // not on the wall: the turf is the plating by then
//	F.sd_LumReset()		//TODO: ~Carn
	return

/// The thermite fire burns out.
/proc/thermite_cleanup(obj/effect/overlay/O)
	if(O)
		dissolved(O)

/turf/simulated/wall/proc/radiate(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	// radioactivity moved to a component on /datum/material.
	var/total_radiation = wall_radioactivity()
	if(!total_radiation)
		return

	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = total_radiation,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = total_radiation
	)
	return total_radiation

/turf/simulated/wall/burn(temperature)
	if(material.combustion_effect(src, temperature, 0.7))
		after(src, 0.2 SECONDS, PROC_REF(burn_collapse), with = list(temperature, girder_material.name))

/turf/simulated/wall/proc/burn_collapse(temperature, girder_mat_name)
	new /obj/structure/girder(src, girder_mat_name)
	src.ChangeTurf(/turf/simulated/floor)
	for(var/turf/simulated/wall/W in range(3,src))
		W.burn((temperature/4))
	for(var/obj/machinery/door/airlock/phoron/D in range(3,src))
		D.ignite(temperature/4)

/turf/simulated/wall/can_engrave()
	return (material && material.hardness >= 10 && material.hardness <= 100)

/turf/simulated/wall/occult_act(mob/living/user)
	to_chat(user, span_cult("You consecrate the wall."))
	ChangeTurf(/turf/simulated/wall/cult, preserve_outdoors = TRUE)
	return TRUE

/// Old click_alt: graffiti with the held item; otherwise the default alt-click.
/turf/simulated/wall/proc/wall_graffiti_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(isliving(user))
		var/mob/living/livingUser = user
		if(try_graffiti(livingUser, livingUser.get_active_hand()))
			return OP_OK
	return OP_DECLINE

// === merged from RCD_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/obj/item/rcd
	allow_concurrent_building = 1
	var/airlock_glass = FALSE // So the floor's rcd_act knows how much ammo to use
	var/advanced_airlock_setting = 1 //Set to 1 if you want more paintjobs available
	var/list/conf_access = null
	var/use_one_access = 0 //If the airlock should require ALL or only ONE of the listed accesses.
	var/girder_type = /obj/structure/girder
	var/frame_type = /obj/structure/frame
	var/wall_frame_type = /obj/machinery/alarm
	var/window_dir = "FULL"
	/// A grille's window direction was just picked; the next rcd_values() on a grille uses window_dir without asking.
	var/window_dir_confirmed = FALSE
	var/emagged = 0
	window_type = "rglass"
	var/turret_faction = null
	var/static/image/radial_image_firelock = image(icon = 'icons/mob/radial.dmi', icon_state = "firelock")
	var/static/image/radial_image_windoor = image(icon= 'icons/mob/radial.dmi', icon_state = "windoor")
	var/static/image/radial_image_frame = image(icon = 'icons/mob/radial.dmi', icon_state = "machine")
	var/static/image/radial_image_wallframe = image(icon = 'icons/mob/radial.dmi', icon_state = "wallframe")
	var/static/image/radial_image_access = image(icon = 'icons/mob/radial.dmi', icon_state = "access")
	var/static/image/radial_image_airlock_type = image(icon = 'icons/mob/radial.dmi', icon_state = "airlocktype")
	var/static/image/radial_image_conveyor = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyor")
	var/static/image/radial_image_turret = image(icon = 'icons/mob/radial.dmi', icon_state = "turret")

/obj/item/rcd/advanced
	can_remove_rwalls = 1



/obj/item/rcd/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	emagged = 1
	to_chat(user, span_warning("You short out the safeties on \the [src]'s construction limiter"))
	return OP_OK

/// Old attackby: load matter cartridges or sheets, then fall through as its ..() did.
/obj/item/rcd/proc/rcd_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/loaded = 0
	if(istype(W, /obj/item/rcd_ammo))
		var/obj/item/rcd_ammo/cartridge = W
		var/can_store = min(max_stored_matter - stored_matter, cartridge.remaining)
		if(can_store <= 0)
			to_chat(user, span_warning("There's either no space or \the [cartridge] is empty!"))
			return OP_PASS
		set_stored_matter(stored_matter + can_store)
		cartridge.remaining -= can_store
		if(!cartridge.remaining)
			to_chat(user, span_warning("\The [cartridge] dissolves as it empties of compressed matter."))
			consume(W, user)
		loaded = 1
	if(istype(W,/obj/item/stack))
		var/obj/item/stack/S = W
		if(istype(S,/obj/item/stack/material/glass/phoronrglass))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*4, user)
		else if(istype(S,/obj/item/stack/material/glass/phoronglass))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*3, user)
		else if(istype(S,/obj/item/stack/material/glass/reinforced))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*2, user)
		else if(istype(S,/obj/item/stack/material/plasteel))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*4, user)
		else if(istype(S,/obj/item/stack/rods))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*0.66, user)
		else if(istype(S,/obj/item/stack/tile/floor))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*0.33, user)
		else if(istype(S,/obj/item/stack/material/steel))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*1.33, user)
		else if(istype(S,/obj/item/stack/material/glass))
			loaded = loadwithsheets(S, RCD_SHEETS_PER_MATTER_UNIT*1.33, user)
	if(loaded)
		play_sfx(src, SFX_MACHINES_CLICK)
		to_chat(user, span_notice("The RCD now holds [stored_matter]/[max_stored_matter] matter-units."))
	return OP_DECLINE

/obj/item/rcd/proc/loadwithsheets(obj/item/stack/S, value, mob/user)
	var/maxsheets = round((max_stored_matter-stored_matter)/value)    //calculate the max number of sheets that will fit in RCD
	if(maxsheets > 0)
		var/amount_to_use = min(S.amount, maxsheets)
		S.use(amount_to_use)
		set_stored_matter(stored_matter + value*amount_to_use)
		to_chat(user, span_notice("You insert [amount_to_use] [S.name] sheets into [src]. "))
		return 1
	to_chat(user, span_warning("You can't insert any more [S.name] sheets into [src]!"))
	return 0

/// Old attack_self: the mode radial menu.
/obj/item/rcd/proc/rcd_self(datum/act/op/A)
	var/mob/living/user = A.actor
	var/list/choices = list(
		"Floors & Walls" = radial_image_floorwall,
		"Airlock" = radial_image_airlock,
		"Windoor" = radial_image_windoor,
		"Firelock" = radial_image_firelock,
		"Deconstruct" = radial_image_decon,
		"Grilles & Windows" = radial_image_grillewind,
		"Frames" = radial_image_frame,
		"WallFrames" = radial_image_wallframe,
		"Change Access" = radial_image_access,
		"Change Airlock Type" = radial_image_airlock_type,
		"Conveyors" = radial_image_conveyor
		)
	if(emagged)
		choices["Turrets"] = radial_image_turret
	open_request(src, /datum/prompt/choice, PROC_REF(rcd_mode_chosen), answerer = user, choices = choices, anchor = user, radius = 42, tooltips = TRUE, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/obj/item/rcd/proc/rcd_mode_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/user = A.request.answerer
	var/choice = A.answer.value
	if(!check_menu(user))
		return
	switch(choice)
		if("Floors & Walls")
			var/list/wall_types = list(
			"DEFAULT" = image(icon = 'icons/mob/radial.dmi', icon_state = "default"),
			"BAY" = image(icon = 'icons/mob/radial.dmi', icon_state = "bay"),
			"ERIS" = image(icon = 'icons/mob/radial.dmi', icon_state = "eris")
			)
			// optional: a cancelled sub-pick still switches the mode, as before.
			open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(rcd_girder_chosen), answerer = user, choices = wall_types, anchor = src, require_near = TRUE, tooltips = TRUE, optional_pick = TRUE)
			return
		if("Airlock")
			mode_index = rcd_mode_index(RCD_AIRLOCK)
		if("Windoor")
			mode_index = rcd_mode_index(RCD_WINDOOR)
		if("Firelock")
			mode_index = rcd_mode_index(RCD_FIRELOCK)
		if("Deconstruct")
			mode_index = rcd_mode_index(RCD_DECONSTRUCT)
		if("Grilles & Windows")
			mode_index = rcd_mode_index(RCD_WINDOWGRILLE)
		if("Frames")
			mode_index = rcd_mode_index(RCD_FRAME)
		if("WallFrames")
			var/list/wall_frame_types = list(
			"Air Alarm" = image(icon = 'icons/mob/radial.dmi', icon_state = "wallframe"),
			"Light Bulb" = image(icon = 'icons/mob/radial.dmi', icon_state = "lightbulb"),
			"Light Tube" = image(icon = 'icons/mob/radial.dmi', icon_state = "lighttube"),
			"Doorbell Chime" = image(icon = 'icons/mob/radial.dmi', icon_state = "doorbell"),
			"Doorbell Button" = image(icon = 'icons/mob/radial.dmi', icon_state = "doorbellbutton"),
			"Status Display" = image(icon = 'icons/mob/radial.dmi', icon_state = "status"),
			"Supply Requests Console" = image(icon = 'icons/mob/radial.dmi', icon_state = "supply"),
			"ATM" = image(icon = 'icons/mob/radial.dmi', icon_state = "atm"),
			"Newscaster" = image(icon = 'icons/mob/radial.dmi', icon_state = "newscaster"),
			"Wall Charger" = image(icon = 'icons/mob/radial.dmi', icon_state = "wallcharger"),
			"Fire Alarm" = image(icon = 'icons/mob/radial.dmi', icon_state = "firealarm"),
			"Guest Pass Terminal" = image(icon = 'icons/mob/radial.dmi', icon_state = "guestpass"),
			"Intercom" = image(icon = 'icons/mob/radial.dmi', icon_state = "intercom"),
			"Keycard Authenticator" = image(icon = 'icons/mob/radial.dmi', icon_state = "keycardauth"),
			"Geiger Counter" = image(icon = 'icons/mob/radial.dmi', icon_state = "geiger"),
			"Electrochromic Window Button" = image(icon = 'icons/mob/radial.dmi', icon_state = "windowtint"),
			"ID Restoration Terminal" = image(icon = 'icons/mob/radial.dmi', icon_state = "idrestore"),
			"Timeclock Terminal" = image(icon = 'icons/mob/radial.dmi', icon_state = "timeclock"),
			"Station Map" = image(icon = 'icons/mob/radial.dmi', icon_state = "stationmap"),
			"AI Status Display" = image(icon = 'icons/mob/radial.dmi', icon_state = "status"),
			"Light Switch" = image(icon = 'icons/mob/radial.dmi', icon_state = "lightswitch"),
			"Entertainment Monitor" = image(icon = 'icons/mob/radial.dmi', icon_state = "entertainment")
			)
			open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(rcd_wall_frame_chosen), answerer = user, choices = wall_frame_types, anchor = src, require_near = TRUE, tooltips = TRUE, optional_pick = TRUE)
			return
		if("Change Access")
			change_airlock_access(user)
			return
		if("Change Airlock Type")
			change_airlock_setting(user)
			return
		if("Conveyors")
			mode_index = rcd_mode_index(RCD_CONVEYOR)
		if("Turrets")
			var/list/turret_factions = list(
			"HOSTILE TO ALL" = image(icon = 'icons/mob/radial.dmi', icon_state = "turret1"),
			"HOSTILE TO ENEMIES" = image(icon = 'icons/mob/radial.dmi', icon_state = "turret2")
			)
			open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(rcd_turret_faction_chosen), answerer = user, choices = turret_factions, anchor = src, require_near = ranged?FALSE:TRUE, tooltips = TRUE, optional_pick = TRUE)
			return
		else
			return
	rcd_mode_changed(user, choice)

/// The mode radial's (and its sub-radials') last step.
/obj/item/rcd/proc/rcd_mode_changed(mob/living/user, choice)
	play_sfx(src, SFX_EFFECTS_POP)
	to_chat(user, span_notice("You change RCD's mode to '[choice]'."))

/obj/item/rcd/proc/rcd_girder_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	if(!check_menu(user))
		return
	switch(ask.value)
		if("DEFAULT")
			girder_type = /obj/structure/girder
		if("BAY")
			girder_type = /obj/structure/girder/bay
		if("ERIS")
			girder_type = /obj/structure/girder/eris
	mode_index = rcd_mode_index(RCD_FLOORWALL)
	rcd_mode_changed(user, "Floors & Walls")

/obj/item/rcd/proc/rcd_wall_frame_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	if(!check_menu(user))
		return
	switch(ask.value)
		if("Air Alarm")
			wall_frame_type = /obj/machinery/alarm
		if("Light Bulb")
			wall_frame_type = /obj/machinery/light/small
		if("Light Tube")
			wall_frame_type = /obj/machinery/light
		if("Doorbell Chime")
			wall_frame_type = /obj/machinery/doorbell_chime
		if("Doorbell Button")
			wall_frame_type = /obj/machinery/button/doorbell
		if("Status Display")
			wall_frame_type = /obj/machinery/status_display
		if("Supply Requests Console")
			wall_frame_type = /obj/machinery/requests_console
		if("ATM")
			wall_frame_type = /obj/machinery/atm
		if("Newscaster")
			wall_frame_type = /obj/machinery/newscaster
		if("Wall Charger")
			wall_frame_type = /obj/machinery/recharger/wallcharger
		if("Fire Alarm")
			wall_frame_type = /obj/machinery/firealarm
		if("Guest Pass Terminal")
			wall_frame_type = /obj/machinery/computer/guestpass
		if("Intercom")
			wall_frame_type = /obj/item/radio/intercom
		if("Keycard Authenticator")
			wall_frame_type = /obj/machinery/keycard_auth
		if("Geiger Counter")
			wall_frame_type = /obj/item/geiger/wall
		if("Electrochromic Window Button")
			wall_frame_type = /obj/machinery/button/windowtint
		if("ID Restoration Terminal")
			wall_frame_type = /obj/machinery/computer/id_restorer
		if("Timeclock Terminal")
			wall_frame_type = /obj/machinery/computer/timeclock
		if("Station Map")
			wall_frame_type = /obj/machinery/station_map
		if("AI Status Display")
			wall_frame_type = /obj/machinery/ai_status_display
		if("Light Switch")
			wall_frame_type = /obj/machinery/light_switch
		if("Entertainment Monitor")
			wall_frame_type = /obj/machinery/computer/security/telescreen/entertainment

	mode_index = rcd_mode_index(RCD_WALLFRAME)
	rcd_mode_changed(user, "WallFrames")

/obj/item/rcd/proc/rcd_turret_faction_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	if(!check_menu(user))
		return
	switch(ask.value)
		if("HOSTILE TO ALL")
			turret_faction = null
		if("HOSTILE TO ENEMIES")
			turret_faction = user.faction
	mode_index = rcd_mode_index(RCD_TURRET)
	rcd_mode_changed(user, "Turrets")

/obj/item/rcd/proc/get_airlock_image(airlock_type)
	var/obj/machinery/door/airlock/proto = airlock_type
	var/ic = initial(proto.icon)
	var/mutable_appearance/MA = mutable_appearance(ic, "door_closed")
	if(!initial(proto.glass))
		MA.overlays += "fill_closed"
	//Not scaling these down to button size because they look horrible then, instead just bumping up radius.
	return MA

/obj/item/rcd/proc/change_airlock_setting(mob/user)
	if(!user)
		return

	var/list/solid_or_glass_choices = list(
		"Solid" = get_airlock_image(/obj/machinery/door/airlock),
		"Glass" = get_airlock_image(/obj/machinery/door/airlock/glass)
	)

	// optional: a cancelled pick falls back to the default airlock, as before.
	open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(airlock_category_chosen), answerer = user, choices = solid_or_glass_choices, anchor = src, require_near = TRUE, optional_pick = TRUE)

/obj/item/rcd/proc/airlock_category_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	if(!check_menu(user))
		return
	switch(ask.value)
		if("Solid")
			if(advanced_airlock_setting == 1)
				var/list/solid_choices = list(
					"Standard" = get_airlock_image(/obj/machinery/door/airlock),
					"Engineering" = get_airlock_image(/obj/machinery/door/airlock/engineering),
					"Atmospherics" = get_airlock_image(/obj/machinery/door/airlock/atmos),
					"Security" = get_airlock_image(/obj/machinery/door/airlock/security),
					"Command" = get_airlock_image(/obj/machinery/door/airlock/command),
					"Medical" = get_airlock_image(/obj/machinery/door/airlock/medical),
					"Research" = get_airlock_image(/obj/machinery/door/airlock/research),
					"Freezer" = get_airlock_image(/obj/machinery/door/airlock/freezer),
					"Science" = get_airlock_image(/obj/machinery/door/airlock/science),
					"Mining" = get_airlock_image(/obj/machinery/door/airlock/mining),
					"Maintenance" = get_airlock_image(/obj/machinery/door/airlock/maintenance),
					"External" = get_airlock_image(/obj/machinery/door/airlock/external),
					"Airtight Hatch" = get_airlock_image(/obj/machinery/door/airlock/hatch),
					"Maintenance Hatch" = get_airlock_image(/obj/machinery/door/airlock/maintenance_hatch)
				)
				open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(airlock_solid_paint_chosen), answerer = user, choices = solid_choices, anchor = src, radius = 42, require_near = TRUE, optional_pick = TRUE)
			else
				airlock_type = /obj/machinery/door/airlock
				airlock_glass = FALSE

		if("Glass")
			if(advanced_airlock_setting == 1)
				var/list/glass_choices = list(
					"Standard" = get_airlock_image(/obj/machinery/door/airlock/glass),
					"Engineering" = get_airlock_image(/obj/machinery/door/airlock/glass_engineering),
					"Atmospherics" = get_airlock_image(/obj/machinery/door/airlock/glass_atmos),
					"Security" = get_airlock_image(/obj/machinery/door/airlock/glass_security),
					"Command" = get_airlock_image(/obj/machinery/door/airlock/glass_command),
					"Medical" = get_airlock_image(/obj/machinery/door/airlock/glass_medical),
					"Research" = get_airlock_image(/obj/machinery/door/airlock/glass_research),
					"Science" = get_airlock_image(/obj/machinery/door/airlock/glass_science),
					"Mining" = get_airlock_image(/obj/machinery/door/airlock/glass_mining),
					"External" = get_airlock_image(/obj/machinery/door/airlock/glass_external),
				)
				open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(airlock_glass_paint_chosen), answerer = user, choices = glass_choices, anchor = src, radius = 42, require_near = TRUE, optional_pick = TRUE)
			else
				airlock_type = /obj/machinery/door/airlock/glass
				airlock_glass = TRUE
		else
			airlock_type = /obj/machinery/door/airlock
			airlock_glass = FALSE

/obj/item/rcd/proc/airlock_solid_paint_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	if(!check_menu(user))
		return
	switch(ask.value)
		if("Standard")
			airlock_type = /obj/machinery/door/airlock
		if("Engineering")
			airlock_type = /obj/machinery/door/airlock/engineering
		if("Atmospherics")
			airlock_type = /obj/machinery/door/airlock/atmos
		if("Security")
			airlock_type = /obj/machinery/door/airlock/security
		if("Command")
			airlock_type = /obj/machinery/door/airlock/command
		if("Medical")
			airlock_type = /obj/machinery/door/airlock/medical
		if("Research")
			airlock_type = /obj/machinery/door/airlock/research
		if("Freezer")
			airlock_type = /obj/machinery/door/airlock/freezer
		if("Science")
			airlock_type = /obj/machinery/door/airlock/science
		if("Mining")
			airlock_type = /obj/machinery/door/airlock/mining
		if("Maintenance")
			airlock_type = /obj/machinery/door/airlock/maintenance
		if("External")
			airlock_type = /obj/machinery/door/airlock/external
		if("Airtight Hatch")
			airlock_type = /obj/machinery/door/airlock/hatch
		if("Maintenance Hatch")
			airlock_type = /obj/machinery/door/airlock/maintenance_hatch
	airlock_glass = FALSE

/obj/item/rcd/proc/airlock_glass_paint_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	if(!check_menu(user))
		return
	switch(ask.value)
		if("Standard")
			airlock_type = /obj/machinery/door/airlock/glass
		if("Engineering")
			airlock_type = /obj/machinery/door/airlock/glass_engineering
		if("Atmospherics")
			airlock_type = /obj/machinery/door/airlock/glass_atmos
		if("Security")
			airlock_type = /obj/machinery/door/airlock/glass_security
		if("Command")
			airlock_type = /obj/machinery/door/airlock/glass_command
		if("Medical")
			airlock_type = /obj/machinery/door/airlock/glass_medical
		if("Research")
			airlock_type = /obj/machinery/door/airlock/glass_research
		if("Science")
			airlock_type = /obj/machinery/door/airlock/glass_science
		if("Mining")
			airlock_type = /obj/machinery/door/airlock/glass_mining
		if("External")
			airlock_type = /obj/machinery/door/airlock/glass_external
	airlock_glass = TRUE

/obj/item/rcd/proc/change_airlock_access(mob/user)

	if (!ishuman(user) && !istype(user,/mob/living/silicon/robot))
		return

	var/t1 = ""

	if(use_one_access)
		t1 += "Restriction Type: <a href='byond://?src=[REF(src)];access=one'>At least one access required</a><br>"
	else
		t1 += "Restriction Type: <a href='byond://?src=[REF(src)];access=one'>All accesses required</a><br>"

	t1 += "<a href='byond://?src=[REF(src)];access=all'>Remove All</a><br>"

	var/accesses = ""
	accesses += "<div align='center'>" + span_bold("Access") + "</div>"
	accesses += "<table style='width:100%'>"
	accesses += "<tr>"
	for(var/i = 1; i <= 7; i++)
		accesses += "<td style='width:14%'>" + span_bold("[SSaccess.get_region_accesses_name(i)]:") + "</td>"
	accesses += "</tr><tr>"
	for(var/i = 1; i <= 7; i++)
		accesses += "<td style='width:14%' valign='top'>"
		for(var/A in SSaccess.get_region_accesses(i))
			if(A in conf_access)
				accesses += "<a href='byond://?src=[REF(src)];access=[A]'>" + span_red("[replacetext(SSaccess.get_access_desc(A), " ", "&nbsp")]") + "</a> "
			else
				accesses += "<a href='byond://?src=[REF(src)];access=[A]'>[replacetext(SSaccess.get_access_desc(A), " ", "&nbsp")]</a> "
			accesses += "<br>"
		accesses += "</td>"
	accesses += "</tr></table>"
	t1 += "<tt>[accesses]</tt>"

	t1 += "<p><a href='byond://?src=[REF(src)];close=1'>Close</a></p>\n"

	// structured TGUI AdminReport; byond:// links forwarded to host.
	dq_admin_report_html(user, "Access Control", t1, src)


/obj/item/rcd/topic_usable(datum/act/op/A)
	. = ..()
	if(!.)
		return
	if(A.actor.stat || A.actor.restrained())
		return FALSE

/obj/item/rcd/proc/topic_close(datum/act/op/A)
	// close TGUI window
	SStgui.close_uis(src)
	return TRUE

/obj/item/rcd/proc/topic_access(datum/act/op/A, href_access)
	var/mob/user = A.actor
	toggle_access(href_access)
	change_airlock_access(user)
	return TRUE

/obj/item/rcd/proc/toggle_access(acc)
	if (acc == "all")
		conf_access = null
	else if(acc == "one")
		use_one_access = !use_one_access
	else
		var/req = text2num(acc)

		if (conf_access == null)
			conf_access = list()

		if (!(req in conf_access))
			conf_access += req
		else
			conf_access -= req
			if (!conf_access.len)
				conf_access = null

//Storing all the RCD acts and values here for ease of navigation
//////////////////////////////////////
///////////////TURF///////////////////
//////////////////////////////////////
/turf/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(density || !can_build_into_floor)
		return FALSE
	if(passed_mode == RCD_FLOORWALL)
		var/obj/structure/lattice/L = locate_on(src, /obj/structure/lattice)
		// A lattice costs one rod to make. A sheet can make two rods, meaning a lattice costs half of a sheet.
		// A sheet also makes four floor tiles, meaning it costs 1/4th of a sheet to place a floor tile on a lattice.
		// Therefore it should cost 3/4ths of a sheet if a lattice is not present, or 1/4th of a sheet if it does.
		return rcd_value_entry(RCD_FLOORWALL, 0, L ? RCD_SHEETS_PER_MATTER_UNIT * 0.25 : RCD_SHEETS_PER_MATTER_UNIT * 0.75)
	return FALSE

/turf/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_FLOORWALL)
		to_chat(user, span_notice("You build a floor."))
		ChangeTurf(/turf/simulated/floor/airless, preserve_outdoors = TRUE)
		return TRUE
	return FALSE

//////////////////////////////////////
///////////////FLOOR//////////////////
//////////////////////////////////////
/turf/simulated/floor/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_FLOORWALL)
			var/obj/structure/girder/G = locate_on(src, /obj/structure/girder)
			if(G)
				the_rcd.use_rcd(G, user)
				return 1
			// A wall costs four sheets to build (two for the grider and two for finishing it).
			var/cost = RCD_SHEETS_PER_MATTER_UNIT * 2
			return rcd_value_entry(RCD_FLOORWALL, 0.5 SECONDS, cost)
		if(RCD_AIRLOCK)
			// Airlock assemblies cost four sheets. Let's just add another for the electronics/wires/etc.
			return rcd_value_entry(RCD_AIRLOCK, 5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 5)
		if(RCD_WINDOOR)
			return rcd_value_entry(RCD_WINDOOR, 3 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 3)
		if(RCD_FIRELOCK)
			return rcd_value_entry(RCD_FIRELOCK, 3 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 5)
		if(RCD_WINDOWGRILLE)
			var/obj/structure/grille/G = locate_on(src, /obj/structure/grille)
			if(G)
				the_rcd.use_rcd(G, user)
				return 1
			return rcd_value_entry(RCD_WINDOWGRILLE, 1 SECOND, RCD_SHEETS_PER_MATTER_UNIT * 1)
		if(RCD_DECONSTRUCT)
			//12 floor deconstructions per full RCD
			return rcd_value_entry(RCD_DECONSTRUCT, 3 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 2.5)
		if(RCD_FRAME)
			return rcd_value_entry(RCD_FRAME, 1.5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 5)
		if(RCD_CONVEYOR)
			return rcd_value_entry(RCD_CONVEYOR, 1.5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 6)
		if(RCD_TURRET)
			return rcd_value_entry(RCD_TURRET, 6 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 10)
	return FALSE

/turf/simulated/floor/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_FLOORWALL)
			to_chat(user, span_notice("You build a girder."))
			new the_rcd.girder_type(src)
			return TRUE
		if(RCD_AIRLOCK)
			if(locate_on(src, /obj/machinery/door/airlock))
				return FALSE // No more airlock stacking.
			to_chat(user, span_notice("You build an airlock."))
			var/obj/machinery/door/airlock/A = new the_rcd.airlock_type(src)
			rel_set(A, nameof(A.electronics), new/obj/item/airlock_electronics(A))
			A.electronics.req_access = null
			A.electronics.req_one_access = null
			A.electronics.one_access = null
			if(the_rcd.conf_access)
				if(the_rcd.use_one_access)
					A.electronics.one_access = the_rcd.use_one_access
					A.electronics.req_one_access = the_rcd.conf_access.Copy()
					A.req_one_access = the_rcd.conf_access.Copy()
				else
					A.electronics.conf_access = the_rcd.conf_access.Copy()
					A.req_access = the_rcd.conf_access.Copy()
			A.set_autoclose(TRUE)
			return TRUE
		if(RCD_WINDOOR)
			var/list/windoor_types = list(
			"default" = image(icon = 'icons/mob/radial.dmi', icon_state = "windoor"),
			"secure" = image(icon = 'icons/mob/radial.dmi', icon_state = "swindoor")
			)
			// The build waits on the picks; the matter is paid when the last one lands (finish_deferred_build).
			the_rcd.cleanup_effect(src)
			open_request(src, /datum/prompt/choice/rcd_build_review, PROC_REF(rcd_windoor_type_chosen), answerer = user, choices = windoor_types, anchor = src, rcd = the_rcd, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			return FALSE
		if(RCD_FIRELOCK)
			if(locate_on(src, /obj/machinery/door/firedoor))
				return FALSE
			to_chat(user, span_notice("You build a firelock."))
			new /obj/machinery/door/firedoor/glass(src)
			return TRUE
		if(RCD_WINDOWGRILLE)
			if(locate_on(src, /obj/structure/grille))
				return FALSE
			to_chat(user, span_notice("You construct the grille."))
			var/obj/structure/grille/G = new(src)
			G.set_anchored(TRUE)
			return TRUE
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			ChangeTurf(get_base_turf_by_area(src), preserve_outdoors = TRUE)
			return TRUE
		if(RCD_FRAME)
			var/list/frame_types = list(
			"Machine" = image(icon = 'icons/mob/radial.dmi', icon_state = "machine"),
			"Computer" = image(icon = 'icons/mob/radial.dmi', icon_state = "computer_dir")
			)
			the_rcd.cleanup_effect(src)
			open_request(src, /datum/prompt/choice/rcd_build_review, PROC_REF(rcd_frame_type_chosen), answerer = user, choices = frame_types, anchor = src, rcd = the_rcd, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			return FALSE
		if(RCD_CONVEYOR)
			var/list/conveyor_dirs = list(
			"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyorn"),
			"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyore"),
			"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyors"),
			"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = "conveyorw")
			)
			the_rcd.cleanup_effect(src)
			open_request(src, /datum/prompt/choice/rcd_build_review, PROC_REF(rcd_conveyor_dir_chosen), answerer = user, choices = conveyor_dirs, anchor = src, rcd = the_rcd, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
			return FALSE
		if(RCD_TURRET)
			if(locate_on(src, /obj/machinery/porta_turret))
				return FALSE
			var/obj/machinery/porta_turret/T = new /obj/machinery/porta_turret/rcd(src)
			T.faction = the_rcd.turret_faction
			return TRUE

/// A floor build that asks what to make after the RCD's timer: it carries the RCD and the picks so far.
/datum/prompt/choice/rcd_option_review
	timeout = 0
	radial = TRUE
	autopick_single_option = TRUE
	var/optional_pick = FALSE

/// Optional RCD menus deliberately apply their existing null-choice fallback on explicit cancellation.
/datum/prompt/choice/rcd_option_review/proc/deliver_pick()
	var/mob/user = answerer
	if(!istype(user) || QDELETED(user) || !length(choices))
		return FALSE
	return outcome == REQ_ANSWERED || (optional_pick && outcome == REQ_CANCELLED && isnull(value))

/datum/prompt/choice/rcd_build_review
	parent_type = /datum/prompt/choice/rcd_option_review
	var/obj/item/rcd/rcd
	var/windoor_type
	var/windoor_dir
	var/frame_type

CAPABILITIES(/datum/prompt/choice/rcd_build_review)
	ref_one(nameof(rcd), /obj/item/rcd)

/datum/prompt/choice/rcd_build_review/prepare(datum/act/A)
	var/obj/item/rcd/captured = rcd
	rel_clear(src, nameof(rcd))
	if(captured)
		rel_set(src, nameof(rcd), captured)
	return ..()

/datum/prompt/choice/rcd_build_review/recheck_extra()
	if(!istype(rcd) || QDELETED(rcd))
		return "gone"
	return ..()

/// The pick can still be built: the RCD is usable and can pay for `mode` here.
/turf/simulated/floor/proc/rcd_build_pick_ok(datum/prompt/choice/rcd_build_review/ask, mode)
	var/obj/item/rcd/rcd = ask.rcd
	if(!ask.value || !rcd.check_menu(ask.answerer))
		return FALSE
	var/list/results = rcd_values(ask.answerer, rcd, mode)
	if(!islist(results))
		return FALSE
	var/cost = results[RCD_VALUE_COST]
	if(!rcd.can_afford(cost * rcd.power_output_envelope(cost)))
		to_chat(ask.answerer, span_warning("\The [rcd] lacks the required material to finish the operation."))
		return FALSE
	return TRUE

/// Pays for a build whose rcd_act() deferred to a radial (use_rcd_timed_done's tail).
/obj/item/rcd/proc/finish_deferred_build(atom/A, mob/living/user, mode)
	var/list/results = A.rcd_values(user, src, mode)
	if(!islist(results))
		return
	var/cost = results[RCD_VALUE_COST]
	var/output_envelope = power_output_envelope(cost)
	consume_resources(cost * output_envelope)
	record_enhanced_output(cost, output_envelope)
	play_sfx(A, SFX_ITEMS_DECONSTRUCT)

/turf/simulated/floor/proc/rcd_windoor_type_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/rcd_build_review/ask = context.request
	if(!rcd_build_pick_ok(ask, RCD_WINDOOR))
		return
	var/selected_windoor_type = ask.value
	var/list/windoor_dirs = list(
	"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoorn":"swindoorn")),
	"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoore":"swindoore")),
	"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoors":"swindoors")),
	"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"windoorw":"swindoorw"))
	)
	open_request(src, /datum/prompt/choice/rcd_build_review, PROC_REF(rcd_windoor_dir_chosen), answerer = ask.answerer, choices = windoor_dirs, anchor = src, rcd = ask.rcd, windoor_type = selected_windoor_type, require_near = ask.require_near, tooltips = TRUE)

/turf/simulated/floor/proc/rcd_windoor_dir_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/rcd_build_review/ask = context.request
	if(!rcd_build_pick_ok(ask, RCD_WINDOOR))
		return
	var/selected_windoor_type = ask.windoor_type
	var/list/windoor_open_dirs = list(
	"left" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"left":"leftsecure")),
	"right" = image(icon = 'icons/mob/radial.dmi', icon_state = (selected_windoor_type=="default"?"right":"rightsecure"))
	)
	open_request(src, /datum/prompt/choice/rcd_build_review, PROC_REF(rcd_windoor_open_dir_chosen), answerer = ask.answerer, choices = windoor_open_dirs, anchor = src, rcd = ask.rcd, windoor_type = selected_windoor_type, windoor_dir = ask.value, require_near = ask.require_near, tooltips = TRUE)

/turf/simulated/floor/proc/rcd_windoor_open_dir_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/rcd_build_review/ask = context.request
	if(!rcd_build_pick_ok(ask, RCD_WINDOOR))
		return
	var/obj/item/rcd/rcd = ask.rcd
	var/selected_windoor_type = ask.windoor_type
	var/selected_windoor_dir = ask.windoor_dir
	var/selected_windoor_open_dir = ask.value
	var/obj/machinery/door/window/A = new(src)
	if(selected_windoor_type == "default")
		selected_windoor_type = ""
	A.icon_state = selected_windoor_open_dir+selected_windoor_type
	A.base_state = selected_windoor_open_dir+selected_windoor_type
	switch(selected_windoor_dir)
		if("NORTH")
			A.dir = NORTH
		if("SOUTH")
			A.dir = SOUTH
		if("EAST")
			A.dir = EAST
		if("WEST")
			A.dir = WEST
	if(selected_windoor_type == "secure")
		A.max_integrity = 300
		A.update_integrity(A.max_integrity)
	rel_set(A, nameof(A.electronics), new/obj/item/airlock_electronics(A))
	A.electronics.req_access = null
	A.electronics.req_one_access = null
	A.electronics.one_access = null
	if(rcd.conf_access)
		if(rcd.use_one_access)
			A.electronics.one_access = rcd.use_one_access
			A.electronics.req_one_access = rcd.conf_access.Copy()
			A.req_one_access = rcd.conf_access.Copy()
		else
			A.electronics.conf_access = rcd.conf_access.Copy()
			A.req_access = rcd.conf_access.Copy()
	A.set_autoclose(TRUE)
	rcd.finish_deferred_build(src, ask.answerer, RCD_WINDOOR)

/turf/simulated/floor/proc/rcd_frame_type_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/rcd_build_review/ask = context.request
	if(!rcd_build_pick_ok(ask, RCD_FRAME))
		return
	var/list/frame_dirs = list(
	"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "cnorth"),
	"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = "ceast"),
	"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "csouth"),
	"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = "cwest")
	)
	open_request(src, /datum/prompt/choice/rcd_build_review, PROC_REF(rcd_frame_dir_chosen), answerer = ask.answerer, choices = frame_dirs, anchor = src, rcd = ask.rcd, frame_type = ask.value, require_near = ask.require_near, tooltips = TRUE)

/turf/simulated/floor/proc/rcd_frame_dir_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/rcd_build_review/ask = context.request
	if(!rcd_build_pick_ok(ask, RCD_FRAME))
		return
	var/mob/living/user = ask.answerer
	var/selected_frame_type = ask.frame_type
	var/selected_frame_dir = ask.value
	var/obj/structure/frame
	if(selected_frame_type == "Machine")
		frame = new/obj/structure/frame(src)
	else
		frame = new/obj/structure/frame/computer(src)
	switch(selected_frame_dir)
		if("NORTH")
			frame.set_dir(NORTH)
		if("SOUTH")
			frame.set_dir(SOUTH)
		if("EAST")
			frame.set_dir(EAST)
		if("WEST")
			frame.set_dir(WEST)
	frame.set_anchored(1)
	to_chat(user, span_notice("You build a frame"))
	ask.rcd.finish_deferred_build(src, user, RCD_FRAME)

/turf/simulated/floor/proc/rcd_conveyor_dir_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/rcd_build_review/ask = context.request
	if(!rcd_build_pick_ok(ask, RCD_CONVEYOR))
		return
	var/mob/living/user = ask.answerer
	var/selected_conveyor_dir = ask.value
	var/obj/machinery/conveyor/C = new(src)
	switch(selected_conveyor_dir)
		if("NORTH")
			C.set_dir(NORTH)
		if("SOUTH")
			C.set_dir(SOUTH)
		if("EAST")
			C.set_dir(EAST)
		if("WEST")
			C.set_dir(WEST)
	to_chat(user, span_notice("You build a conveyor"))
	ask.rcd.finish_deferred_build(src, user, RCD_CONVEYOR)

//////////////////////////////////////
//////////////WALL////////////////////
//////////////////////////////////////
/turf/simulated/wall/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			if(material.integrity > 1000) // Don't decon things like elevatorium.
				return FALSE
			if(reinf_material && !the_rcd.can_remove_rwalls) // Gotta do it the old fashioned way if your RCD can't.
				return FALSE
			var/delay_to_use = material.integrity / 3 // Steel has 150 integrity, so it'll take five seconds to down a regular wall.
			if(reinf_material)
				delay_to_use += reinf_material.integrity / 3
			return rcd_value_entry(RCD_DECONSTRUCT, delay_to_use, RCD_SHEETS_PER_MATTER_UNIT * 2.5)
		if(RCD_WALLFRAME)
			return rcd_value_entry(RCD_WALLFRAME, 1, RCD_SHEETS_PER_MATTER_UNIT * 3)
	return FALSE

/turf/simulated/wall/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			ChangeTurf(/turf/simulated/floor/airless, preserve_outdoors = TRUE)
			return TRUE
		if(RCD_WALLFRAME)
			if(!user || !x || !y || !user.x || !user.y) return
			var/dx = user.x - x
			var/dy = user.y - y
			if(!dx && !dy) return

			var/direction
			if(abs(dx) < abs(dy))
				if(dy > 0)	direction = NORTH
				else		direction = SOUTH
			else
				if(dx > 0)	direction = EAST
				else		direction = WEST
			if(gotwallitem(get_step(src,direction), direction))
				to_chat(user, span_warning("There is already a wall item there!"))
				return FALSE
			var/obj/O = new the_rcd.wall_frame_type(get_step(src,direction))
			O.dir = direction
			if(istype(O,/obj/machinery/light))
				O.dir = GLOB.reverse_dir[O.dir]
				return TRUE
			var/static/list/adjusts = list(
			/obj/machinery/computer/security/telescreen/entertainment,
			/obj/machinery/ai_status_display,
			/obj/machinery/station_map,
			/obj/machinery/recharger/wallcharger,
			/obj/machinery/status_display
			)
			var/adjust_val = 0
			for(var/A in adjusts)
				if(istype(O,A))
					adjust_val = 6
					break
			switch(direction)
				if(NORTH)
					O.pixel_x = 0
					O.pixel_y = -26 - adjust_val
				if(SOUTH)
					O.pixel_x = 0
					O.pixel_y = 26 + adjust_val
				if(EAST)
					O.pixel_x = -26 - adjust_val
					O.pixel_y = 0
				if(WEST)
					O.pixel_x = 26 + adjust_val
					O.pixel_y = 0
			return TRUE
	return FALSE

//////////////////////////////////////
//////////////GIRDER//////////////////
//////////////////////////////////////
/obj/structure/girder/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	var/turf/simulated/T = get_turf(src)
	if(!istype(T) || T.density)
		return FALSE

	switch(passed_mode)
		if(RCD_FLOORWALL)
			// Finishing a wall costs two sheets.
			var/cost = RCD_SHEETS_PER_MATTER_UNIT * 2
			// Rwalls cost three to finish.
			if(the_rcd.make_rwalls)
				cost += RCD_SHEETS_PER_MATTER_UNIT * 1
			return rcd_value_entry(RCD_FLOORWALL, 0.5 SECONDS, cost)
		if(RCD_DECONSTRUCT)
			return rcd_value_entry(RCD_DECONSTRUCT, 0.5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/girder/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	var/turf/simulated/T = get_turf(src)
	if(!istype(T) || T.density) // Should stop future bugs of people bringing girders to centcom and RCDing them, or somehow putting a girder on a durasteel wall and deconning it.
		return FALSE

	switch(passed_mode)
		if(RCD_FLOORWALL)
			to_chat(user, span_notice("You finish a wall."))
			// This is mostly the same as using on a floor. The girder's material is preserved, however.
			T.ChangeTurf(wall_type)
			var/turf/simulated/wall/new_T = get_turf(src) // Ref to the wall we just built.
			// Apparently apply_materials(...) for walls requires refs to the material singletons and not strings.
			// This is different from how other material objects with their own set_material(...) do it, but whatever.
			var/datum/material/M = GLOB.name_to_material[the_rcd.material_to_use]
			new_T.apply_materials(M, the_rcd.make_rwalls ? M : null, girder_material)
			new_T.add_hiddenprint(user)
			replaced_by(src, new_T)
			return TRUE

		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			destroyed(src, user, "rcd")
			return TRUE

//////////////////////////////////////
/////////////WINDOW///////////////////
//////////////////////////////////////
/obj/structure/window/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
		if(RCD_WINDOWGRILLE)
			the_rcd.use_rcd(get_turf(src), user)
			return 1

/obj/structure/window/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			destroyed(src, user, "rcd")
			return TRUE
	return FALSE

//////////////////////////////////////
//////////////GRILLE//////////////////
//////////////////////////////////////
/obj/structure/grille/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_WINDOWGRILLE)
			var/construct_cost = 4
			if(destroyed)
				construct_cost = 1
			else
				if(!the_rcd.window_dir_confirmed)
					var/list/window_dirs = list(
					"NORTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "wnorth"),
					"EAST" = image(icon = 'icons/mob/radial.dmi', icon_state = "weast"),
					"SOUTH" = image(icon = 'icons/mob/radial.dmi', icon_state = "wsouth"),
					"WEST" = image(icon = 'icons/mob/radial.dmi', icon_state = "wwest"),
					"FULL" = image(icon = 'icons/mob/radial.dmi', icon_state = "wfull"),
					)
					// Pick first; the answer re-runs use_rcd() with the direction confirmed.
					open_request(src, /datum/prompt/choice/rcd_option_review, PROC_REF(rcd_window_dir_chosen), answerer = user, choices = window_dirs, subject = the_rcd, anchor = src, require_near = the_rcd.ranged?FALSE:TRUE, tooltips = TRUE)
					return 1
				the_rcd.window_dir_confirmed = FALSE
				if(the_rcd.window_dir != "FULL")
					construct_cost = 1
			// A full tile window costs 4 glass sheets.
			return rcd_value_entry(RCD_WINDOWGRILLE, 1 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * construct_cost)
		//Honestly shouldn't cost anything to deconstruct a grille
		if(RCD_DECONSTRUCT)
			return rcd_value_entry(RCD_DECONSTRUCT, 0.5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 0)
	return FALSE

/obj/structure/grille/proc/rcd_window_dir_chosen(datum/act/request/context)
	var/datum/prompt/choice/rcd_option_review/ask = context.request
	if(!ask.deliver_pick())
		return
	var/mob/living/user = ask.answerer
	var/obj/item/rcd/the_rcd = ask.subject
	if(!istype(the_rcd) || !ask.value || !the_rcd.check_menu(user))
		return
	the_rcd.window_dir = ask.value
	the_rcd.window_dir_confirmed = TRUE
	the_rcd.use_rcd(src, user)
	the_rcd.window_dir_confirmed = FALSE

/obj/structure/grille/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			destroyed(src, user, "rcd")
			return TRUE
		if(RCD_WINDOWGRILLE)
			if(destroyed)
				set_destroyed(0)
				repair_damage(max_integrity)
				set_density(1)
				to_chat(user, span_notice("You repair \the [src]."))
				return TRUE
			var/temp_dir
			switch(the_rcd.window_dir)
				if("NORTH")
					temp_dir = NORTH
				if("SOUTH")
					temp_dir = SOUTH
				if("EAST")
					temp_dir = EAST
				if("WEST")
					temp_dir = WEST
				if("FULL")
					temp_dir = 10
			for(var/obj/structure/window/W in src.loc)
				if(W && W.dir == temp_dir)
					to_chat(user, span_warning("There is already a window there."))
					return FALSE

			to_chat(user, span_notice("You construct a window."))
			var/window_to_spawn = /obj/structure/window/basic
			switch(the_rcd.window_type)
				if("glass")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/basic/full":"/obj/structure/window/basic")
				if("rglass")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/reinforced/full":"/obj/structure/window/reinforced")
				if("phoron")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/phoronbasic/full":"/obj/structure/window/phoronbasic")
				if("rphoron")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/phoronreinforced/full":"/obj/structure/window/phoronreinforced")
				if("titanium")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/titanium/full":"/obj/structure/window/titanium")
				if("plastitanium")
					window_to_spawn = (temp_dir==10?"/obj/structure/window/plastitanium/full":"/obj/structure/window/plastitanium")
			var/obj/structure/window/WD = new window_to_spawn(loc)
			WD.set_anchored(TRUE)
			WD.set_dir(temp_dir)
			return TRUE
	return FALSE

//////////////////////////////////////
////////////AIRLOCK///////////////////
//////////////////////////////////////
/obj/machinery/door/airlock/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			//6 deconstructs per full RCD
			return rcd_value_entry(RCD_DECONSTRUCT, 4 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 4)
		if(RCD_FIRELOCK)
			the_rcd.use_rcd(get_turf(src), user)
			return 1
	return FALSE

/obj/machinery/door/airlock/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			destroyed(src, user, "rcd")
			return TRUE
	return FALSE

//////////////////////////////////////
/////////////FIRELOCK/////////////////
//////////////////////////////////////
/obj/machinery/door/firedoor/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 3)
	return FALSE

/obj/machinery/door/firedoor/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE
//////////////////////////////////////
////////////WALL FRAMES///////////////
//////////////////////////////////////
/obj/machinery/computer/security/telescreen/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/computer/security/telescreen/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/doorbell_chime/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/doorbell_chime/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/status_display/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/status_display/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/requests_console/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/requests_console/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/atm/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/atm/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/newscaster/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/newscaster/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/recharger/wallcharger/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/recharger/wallcharger/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/firealarm/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/firealarm/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/alarm/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/alarm/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/computer/guestpass/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/computer/guestpass/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/item/radio/intercom/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/item/radio/intercom/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/keycard_auth/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/keycard_auth/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/item/geiger/wall/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/item/geiger/wall/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/button/windowtint/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/button/windowtint/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/computer/id_restorer/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/computer/id_restorer/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/computer/timeclock/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/computer/timeclock/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/station_map/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/station_map/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/structure/trash_pile/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 8 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/trash_pile/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/structure/loot_pile/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 8 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/loot_pile/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/structure/frame/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/frame/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/ai_status_display/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/ai_status_display/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/light/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/light/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/hologram/holopad/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/hologram/holopad/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/light_switch/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/light_switch/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/structure/table/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/table/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/conveyor/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 2 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/conveyor/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/door/window/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 3 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 3)
	return FALSE

/obj/machinery/door/window/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/structure/firedoor_assembly/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 1 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/firedoor_assembly/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/structure/door_assembly/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 1 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/structure/door_assembly/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/obj/machinery/button/doorbell/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		return rcd_value_entry(RCD_DECONSTRUCT, 1 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 1)
	return FALSE

/obj/machinery/button/doorbell/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	if(passed_mode == RCD_DECONSTRUCT)
		rcd_deconstruct(user)
		return TRUE
	return FALSE

/// The shared RCD deconstruct: tell the user and destroy the target. Every rcd_act() above that
/// simply removes its atom goes through here, so the removal has one site (D-qdel).
/atom/proc/rcd_deconstruct(mob/living/user)
	to_chat(user, span_notice("You deconstruct \the [src]."))
	destroyed(src, user, "rcd")

/// Shared rcd_values() results, keyed by "mode|delay|cost". Callers only read them.
GLOBAL_LIST_EMPTY(rcd_value_entries)

/// The shared, read-only rcd_values() result for (mode, delay, cost): built once per combination.
/proc/rcd_value_entry(mode, delay, cost)
	var/key = "[mode]|[delay]|[cost]"
	var/list/entry = GLOB.rcd_value_entries[key]
	if(!entry)
		entry = list(RCD_VALUE_MODE = mode, RCD_VALUE_DELAY = delay, RCD_VALUE_COST = cost)
		GLOB.rcd_value_entries[key] = entry
	return entry
