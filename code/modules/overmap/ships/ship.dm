#define SHIP_MOVE_RESOLUTION 0.00001
#define MOVING(speed) abs(speed) >= min_speed
#define SANITIZE_SPEED(speed) SIGN(speed) * CLAMP(abs(speed), 0, max_speed)
#define CHANGE_SPEED_BY(speed_var, v_diff) \
	v_diff = SANITIZE_SPEED(v_diff);\
	if(!MOVING(speed_var + v_diff)) \
		{speed_var = 0};\
	else \
		{speed_var = SANITIZE_SPEED((speed_var + v_diff)/(1 + speed_var*v_diff/(max_speed ** 2)))}
// Uses Lorentzian dynamics to avoid going too fast.

/obj/effect/overmap/visitable/ship
	name = "spacecraft"
	desc = "This marker represents a spaceship. Scan it for more information."
	scanner_desc = "Unknown spacefaring vessel."
	dir = NORTH
	icon_state = "ship_nosprite"
	appearance_flags = TILE_BOUND|KEEP_TOGETHER|LONG_GLIDE
	light_power = 4
	layer = OBJ_LAYER + 0.1 // make movables a little higher than regular sectors

	unknown_name = "unknown ship"
	unknown_state = "ship"
	known = TRUE // Ships start known by default because most of them should be transmitting ID codes at all times

	var/vessel_mass = 10000             //tonnes, arbitrary number, affects acceleration provided by engines
	var/vessel_size = SHIP_SIZE_LARGE	//arbitrary number, affects how likely are we to evade meteors
	var/max_speed = 1/(1 SECOND)        //"speed of light" for the ship, in turfs/decisecond.
	var/min_speed = 1/(2 MINUTES)       // Below this, we round speed to 0 to avoid math errors.

	var/position_x						// Pixel coordinates in the world
	var/position_y						// Pixel coordinates in the world.
	// ALLOW(instance_list): d: replaced per instance at runtime (13 assignments)
	var/list/speed = list(0,0)          //speed in x,y direction; replaced (never edited in place) through set_speed()
	COOLDOWN_DECLARE(burn_cooldown)                   //worldtime when ship last acceleated
	var/burn_delay = 1 SECOND           //how often ship can do burns
	var/fore_dir = NORTH                //what dir ship flies towards for purpose of moving stars effect procs

	var/list/engines
	var/engines_state = 0 //global on/off toggle for all engines
	var/thrust_limit = 1  //global thrust limit for all engines, 0..1
	var/halted = 0        //admin halt or other stop.
	// add
	COOLDOWN_DECLARE(sound_cooldown_until) // The last time a ship sound was played // add
	var/sound_cooldown = 10 SECONDS // add

	/// Vis contents overlay holding the ship's vector when in motion
	var/tmp/obj/effect/overlay/vis/vector
	/// Stable registry key used by the unified flight-operations system.
	var/flight_vessel_id
	render_map = TRUE

DECLARE_REGISTRY(/obj/effect/overmap/visitable/ship, REGISTRY_LISTENING_OBJECTS)

/obj/effect/overmap/visitable/ship/Initialize(mapload)
	. = ..()
	min_speed = round(min_speed, SHIP_MOVE_RESOLUTION)
	max_speed = round(max_speed, SHIP_MOVE_RESOLUTION)
	SSshuttles.ships += src
	position_x = 0
	position_y = 0
	rel_set(src, nameof(vector), add_vis_overlay("vector", dir = SOUTH, layer = 10, unique = TRUE))
	vector_overlay().vis_flags = (VIS_INHERIT_PLANE|VIS_INHERIT_ID)
	SSflight?.register_vessel(src)

// leaves the ship list and its flight vessel.
/obj/effect/overmap/visitable/ship/lifecycle_dematerialize()
	SSshuttles.ships -= src
	if(SSflight && flight_vessel_id)
		var/datum/flight_vessel/vessel = own_take_member(SSflight, nameof(/datum/system/flight::vessels), flight_vessel_id)
		if(vessel)
			SSflight.vessel_by_ship -= REF(src)
			spent(vessel)
	return ..()

/obj/effect/overmap/visitable/ship/on_destroy(force)
	remove_vis_overlay(vector_overlay())
	..()

/obj/effect/overmap/visitable/ship/relaymove(mob/user, direction, accel_limit)
	return

/obj/effect/overmap/visitable/ship/proc/is_still()
	return !MOVING(speed[1]) && !MOVING(speed[2])

/// Mirror of "not still": adjust_speed() (the only writer of speed) publishes the start/stop transition through this field.
/obj/effect/overmap/visitable/ship/var/tmp/under_way = FALSE
TRACKED(/obj/effect/overmap/visitable/ship, under_way)
TRACKED(/obj/effect/overmap/visitable/ship, speed)

/// Under way (not still).
CAPABILITIES(/obj/effect/overmap/visitable/ship)
	every(1 SECOND, then(PROC_REF(ship_step)), when = nameof(under_way))
	drag_onto(PROC_REF(drop_input))

/obj/effect/overmap/visitable/ship/proc/is_moving()
	return under_way

/obj/effect/overmap/visitable/ship/get_scan_data(mob/user)
	. = ..()

	if(!is_still())
		. += {"\n\[i\]Heading\[/i\]: [get_heading_degrees()]\n\[i\]Velocity\[/i\]: [get_speed() * 1000]"}
	else
		. += {"\n\[i\]Vessel was stationary at time of scan.\[/i\]\n"}

	var/life = 0

	for(var/mob/living/L in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		if(L.z in map_z) //Things inside things we'll consider shielded, otherwise we'd want to use get_z(L)
			life++

	. += {"\[i\]Life Signs\[/i\]: [life ? life : "None"]"}

//Projected acceleration based on information from engines
/obj/effect/overmap/visitable/ship/proc/get_acceleration()
	return round(get_total_thrust()/get_vessel_mass(), SHIP_MOVE_RESOLUTION)

//Does actual burn and returns the resulting acceleration
/obj/effect/overmap/visitable/ship/proc/get_burn_acceleration()
	return round(thrust_burn() / get_vessel_mass(), SHIP_MOVE_RESOLUTION)

/obj/effect/overmap/visitable/ship/proc/get_vessel_mass()
	. = vessel_mass
	for(var/obj/effect/overmap/visitable/ship/ship in contents_of(src))
		. += ship.get_vessel_mass()

/obj/effect/overmap/visitable/ship/proc/get_speed()
	return round(sqrt(speed[1] ** 2 + speed[2] ** 2), SHIP_MOVE_RESOLUTION)

// Get heading in BYOND dir bits
/obj/effect/overmap/visitable/ship/proc/get_heading()
	var/res = 0
	if(MOVING(speed[1]))
		if(speed[1] > 0)
			res |= EAST
		else
			res |= WEST
	if(MOVING(speed[2]))
		if(speed[2] > 0)
			res |= NORTH
		else
			res |= SOUTH
	return res

// Get heading in degrees (like a compass heading)
/obj/effect/overmap/visitable/ship/proc/get_heading_degrees()
	return (ATAN2(speed[2], speed[1]) + 360) % 360 // Yes ATAN2(y, x) is correct to get clockwise degrees

/obj/effect/overmap/visitable/ship/proc/adjust_speed(n_x, n_y)
	var/old_still = is_still()
	var/new_x = speed[1]
	var/new_y = speed[2]
	CHANGE_SPEED_BY(new_x, n_x)
	CHANGE_SPEED_BY(new_y, n_y)
	set_speed(list(new_x, new_y)) // a new list each time: the tracked write redraws the heading
	var/still = is_still()
	// If nothing changed
	if(still == old_still)
		return
	set_under_way(!still) // is_moving() changed: its declaration starts or stops the work
	// If it is now still, stopped moving
	if(still)
		for(var/zz in map_z)
			SSstarmover.toggle_move_stars(zz)
		if(!COOLDOWN_FINISHED(src, sound_cooldown_until))
			return
		COOLDOWN_START(src, sound_cooldown_until, sound_cooldown)
		for(var/mob/potential_mob as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(potential_mob.z in map_z)
				SEND_SOUND(potential_mob, 'sound/ambience/shutdown.ogg')

	// If it started moving
	else
		glide_size = WORLD_ICON_SIZE/max(DS2TICKS(1 SECOND), 1) //Down to whatever decimal
		for(var/zz in map_z)
			SSstarmover.toggle_move_stars(zz, fore_dir)
		if(!COOLDOWN_FINISHED(src, sound_cooldown_until))
			return
		COOLDOWN_START(src, sound_cooldown_until, sound_cooldown)
		for(var/mob/potential_mob as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(potential_mob.z in map_z)
				SEND_SOUND(potential_mob, 'sound/ambience/startup.ogg')

/obj/effect/overmap/visitable/ship/proc/get_brake_path()
	if(!get_acceleration())
		return INFINITY
	if(is_still())
		return 0
	if(!burn_delay)
		return 0
	if(!get_speed())
		return 0
	var/num_burns = get_speed()/get_acceleration() + 2 //some padding in case acceleration drops form fuel usage
	var/burns_per_grid = 1/ (burn_delay * get_speed())
	return round(num_burns/burns_per_grid)

/obj/effect/overmap/visitable/ship/proc/decelerate()
	adjust_speed(-speed[1], -speed[2])

/obj/effect/overmap/visitable/ship/proc/accelerate(direction, accel_limit)
	return

/obj/effect/overmap/visitable/ship/proc/ship_step(datum/act/timer/A)
	adjust_speed(-speed[1], -speed[2])

// If we get moved, update our internal tracking to account for it
/obj/effect/overmap/visitable/ship/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	// If moving out of another sector start off centered in the turf.
	if(!isturf(old_loc))
		position_x = (WORLD_ICON_SIZE/2) + 1
		position_y = (WORLD_ICON_SIZE/2) + 1
		pixel_x = 0
		pixel_y = 0
	position_x = ((loc.x - 1) * WORLD_ICON_SIZE) + MODULUS(position_x, WORLD_ICON_SIZE)
	position_y = ((loc.y - 1) * WORLD_ICON_SIZE) + MODULUS(position_y, WORLD_ICON_SIZE)
	update_screen()

/// Faces its heading in quarter turns (north while still); the vector overlay follows through its effect.
/obj/effect/overmap/visitable/ship/draw(datum/look/look)
	..()
	if(!is_still())
		var/heading = get_heading_degrees()
		look.set_dir(angle2dir(round(heading, 90)))
		look.effect(PROC_REF(look_effect_vector), heading)
	else
		look.set_dir(NORTH)
		look.effect(PROC_REF(look_effect_vector), null)

/// The vector overlay points along the heading while under way, and rests (pointing south) when still.
/obj/effect/overmap/visitable/ship/proc/look_effect_vector(heading)
	if(isnull(heading))
		vector_overlay().dir = SOUTH
		return
	vector_overlay().dir = NORTH
	vector_overlay().transform = matrix().Turn(heading)

/// The look is the one writer of the heading: set_dir() keeps every other caller facing north.
/obj/effect/overmap/visitable/ship/look_set_dir(new_dir)
	dir = new_dir

/obj/effect/overmap/visitable/ship/set_dir(new_dir)
	return ..(NORTH) // NO! We always face north.

/obj/effect/overmap/visitable/ship/proc/thrust_burn()
	for(var/datum/ship_engine/E in engines)
		. += E.burn()

/obj/effect/overmap/visitable/ship/proc/get_total_thrust()
	for(var/datum/ship_engine/E in engines)
		. += E.get_thrust()

/obj/effect/overmap/visitable/ship/proc/can_burn()
	if(halted)
		return 0
	if (!COOLDOWN_FINISHED(src, burn_cooldown))
		return 0
	for(var/datum/ship_engine/E in engines)
		. |= E.can_burn()

//deciseconds to next step
/obj/effect/overmap/visitable/ship/proc/ETA()
	. = INFINITY
	if(MOVING(speed[1]))
		var/offset = MODULUS(position_x, WORLD_ICON_SIZE)
		var/dist_to_go = (speed[1] > 0) ? (WORLD_ICON_SIZE - offset) : offset
		. = min(., (dist_to_go / abs(speed[1])) * (1/WORLD_ICON_SIZE))
	if(MOVING(speed[2]))
		var/offset = MODULUS(position_y, WORLD_ICON_SIZE)
		var/dist_to_go = (speed[2] > 0) ? (WORLD_ICON_SIZE - offset) : offset
		. = min(., (dist_to_go / abs(speed[2])) * (1/WORLD_ICON_SIZE))
	. = max(., 0)

/obj/effect/overmap/visitable/ship/proc/halt()
	adjust_speed(-speed[1], -speed[2])
	halted = 1

/obj/effect/overmap/visitable/ship/proc/unhalt()
	if(!SSshuttles.overmap_halted)
		halted = 0

/obj/effect/overmap/visitable/ship/populate_sector_objects()
	..()
	for(var/obj/machinery/computer/ship/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		S.attempt_hook_up(src)
	for(var/datum/ship_engine/E in REGISTRY_MEMBERS(REGISTRY_SHIP_ENGINES))
		if(check_ownership(E.holder()))
			rel_add(src, nameof(engines), E)

/obj/effect/overmap/visitable/ship/proc/get_landed_info()
	return "This ship cannot land."

/obj/effect/overmap/visitable/ship/get_distress_info()
	var/datum/flight_vessel/vessel = SSflight?.vessel_for_ship(src)
	var/datum/flight_destination/orbit = SSflight?.destinations[vessel?.orbit_parent_id]
	return "\[ORBIT:[orbit?.name || "unregistered"]\]"

#undef SHIP_MOVE_RESOLUTION
#undef MOVING
#undef SANITIZE_SPEED
#undef CHANGE_SPEED_BY

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/effect/overmap/visitable/ship/proc/drop_input(datum/act/input/A)
	offer_ingestion_with_actor(A.over, A.actor)
	return TRUE

/obj/effect/overmap/visitable/ship/proc/offer_ingestion_with_actor(atom/over, mob/user)
	if(!isliving(over) || !Adjacent(over) || !Adjacent(user))
		return
	if(istype(over, /mob/living/simple_mob/vore/overmap))
		var/mob/living/simple_mob/vore/overmap/sdog = over
		if(!sdog.shipvore)
			return
	var/mob/living/L = over
	var/confirm = rerun_ask(L, "k285", PROC_REF(offer_ingestion_with_actor), args, /datum/prompt/choice, question = "You COULD eat this spaceship...", title = "Eat spaceship?", choices = list("Eat it!", "No, thanks."), buttons = TRUE)
	if(isnull(confirm))
		return
	if(confirm == "Eat it!")
		var/obj/belly/bellychoice = rerun_ask(L, "k287", PROC_REF(offer_ingestion_with_actor), args, /datum/prompt/choice, question = "Which belly?", title = "Select A Belly", choices = L.vore_organs)
		if(isnull(bellychoice))
			return
		if(bellychoice)
			act_message(L, src, MSG_SELF(span_notice("You begin putting %T% into your [bellychoice]!")), \
				MSG_OTHERS(span_warning("%U% is trying to stuff %T% into [L.gender == MALE ? "his" : L.gender == FEMALE ? "her" : "their"] [bellychoice]!")))
			task_timed(L, 5 SECONDS, src, src, PROC_REF(eaten_by), list(L, bellychoice))

/obj/effect/overmap/visitable/ship/proc/eaten_by(mob/living/L, obj/belly/bellychoice)
	forceMove(bellychoice)
	SSskybox.ready().rebuild_skyboxes(map_z)
	act_message(L, null, MSG_SELF("You eat the the spaceship! Yum, metal."), MSG_OTHERS(span_warning("%U% eats a spaceship! This is totally normal.")))

/obj/effect/overmap/visitable/ship/proc/get_people_in_ship()
	. = list()
	for(var/mapz in map_z)
		var/list/thatz = GLOB.players_by_zlevel[mapz]
		. += thatz

/obj/effect/overmap/visitable/ship/hear_talk(mob/talker, list/message_pieces, verb)
	. = ..()

	var/list/listeners = get_people_in_ship()
	for(var/mob/M as anything in listeners)
		M.hear_say(message_pieces, verb, FALSE, talker)

/obj/effect/overmap/visitable/ship/show_message(msg, type, alt, alt_type)
	. = ..()

	var/list/listeners = get_people_in_ship()
	for(var/mob/M as anything in listeners)
		M.show_message(msg, type, alt, alt_type)

/obj/effect/overmap/visitable/ship/see_emote(source, message, m_type)
	. = ..()

	var/list/listeners = get_people_in_ship()
	for(var/mob/M as anything in listeners)
		M.show_message(message, m_type)

/// Accessor for the vector var.
/obj/effect/overmap/visitable/ship/proc/vector_overlay() as /obj/effect/overlay/vis
	return vector
