/turf
	icon = 'icons/turf/floors.dmi'
	layer = TURF_LAYER
	plane = TURF_PLANE
	vis_flags = VIS_INHERIT_ID | VIS_INHERIT_PLANE// Important for interaction with and visualization of openspace.
	level = 1
	var/holy = 0

	// Initial air contents (in moles)
	var/oxygen = 0
	var/carbon_dioxide = 0
	var/nitrogen = 0
	var/phoron = 0
	var/nitrous_oxide = 0
	var/methane = 0

	//* Movement / Pathfinding
	/// How much the turf slows down movement, if any.
	var/slowdown = 0
	/// Pathfinding cost
	var/path_weight = 1
	/// danger flags to avoid
	var/turf_path_danger = NONE
	/// pathfinding id - used to avoid needing a big closed list to iterate through every cycle of jps
	var/pathfinding_cycle

	//Properties for airtight tiles (/wall)
	var/thermal_conductivity = 0.05
	var/heat_capacity = 1

	//Properties for both
	/// The temperature this turf starts at: a seed, read once when its heat cell and its air are built (the map, a
	/// type, or set_temperature() write it). The live temperature is the heat field's: read get_temperature(),
	/// write add_heat()/set_temperature(). DM keeps no other copy (tools/ci/check_grep.sh rejects a turf
	/// `.temperature`).
	var/initial_temperature = T20C
	var/blocks_air = 0          // Does this turf contain air/let air through?

	// General properties.
	var/icon_old = null
	var/pathweight = 1          // How much does it cost to pathfind over this turf?
	var/blessed = 0             // Has the turf been blessed?
	var/dig_exhaustion_chance = 60 // Chance that the digging loot will be exhausted, if set to TURF_DIG_LOOT_EXHAUSTED then the turf is exhausted of loot. if set to TURF_DIG_LOOT_ENDLESS it will never run out.

	var/list/decals

	var/movement_cost = 0       // How much the turf slows down movement, if any.

	var/block_tele = FALSE      // If true, most forms of teleporting to or from this turf tile will fail.
	var/can_build_into_floor = FALSE // Used for things like RCDs (and maybe lattices/floor tiles in the future), to see if a floor should replace it.
	var/list/dangerous_objects // List of 'dangerous' objs that the turf holds that can cause something bad to happen when stepped on, used for AI mobs.
	var/tmp/changing_turf

	var/blocks_nonghost_incorporeal = FALSE
	var/footstep
	var/barefootstep
	var/heavyfootstep
	var/clawfootstep

/turf/simulated/floor
	footstep = FOOTSTEP_FLOOR
	barefootstep = FOOTSTEP_HARD_BAREFOOT
	heavyfootstep = FOOTSTEP_GENERIC_HEAVY
	clawfootstep = FOOTSTEP_HARD_CLAW

/turf/simulated/floor/wood
	footstep = FOOTSTEP_WOOD
	barefootstep = FOOTSTEP_WOOD_BAREFOOT
	clawfootstep = FOOTSTEP_WOOD_CLAW

/turf/simulated/floor/carpet
	footstep = FOOTSTEP_CARPET
	barefootstep = FOOTSTEP_CARPET_BAREFOOT
	clawfootstep = FOOTSTEP_CARPET_BAREFOOT

/turf/simulated/floor/plating
	footstep = FOOTSTEP_PLATING
	barefootstep = FOOTSTEP_HARD_BAREFOOT
	clawfootstep = FOOTSTEP_HARD_CLAW

/turf/simulated/mineral
	footstep = FOOTSTEP_SAND
	barefootstep = FOOTSTEP_SAND
	clawfootstep = FOOTSTEP_SAND

/turf/simulated/floor/outdoors
	footstep = FOOTSTEP_SAND
	barefootstep = FOOTSTEP_SAND
	clawfootstep = FOOTSTEP_SAND

/turf/simulated/floor/outdoors/grass
	footstep = FOOTSTEP_GRASS
	barefootstep = FOOTSTEP_GRASS
	clawfootstep = FOOTSTEP_GRASS

/turf/simulated/floor/water
	footstep = FOOTSTEP_WATER
	barefootstep = FOOTSTEP_WATER
	clawfootstep = FOOTSTEP_WATER

/turf/simulated/floor/lava
	footstep = FOOTSTEP_LAVA
	barefootstep = FOOTSTEP_LAVA
	clawfootstep = FOOTSTEP_LAVA

// ALLOW(init/FRAMEWORK): the turf base of the init chain runs its per-instance setup
/turf/Initialize(mapload)
	. = ..()
	turf_instance_setup()

/turf/table_initialize()
	..()
	turf_instance_setup()

/// The per-turf part of Initialize(), shared with the init_from_table path (atom_type_table.dm).
/turf/proc/turf_instance_setup()
	PRIVATE_PROC(TRUE)
	if(length(contents)) // ALLOW(spatial): hot map-load path (one read per turf); skips the loop setup for empty turfs
		for(var/atom/movable/AM in turf_contents_of_type(src, /atom/movable))
			Entered(AM)

	//Lighting related
	set_luminosity(!(dynamic_lighting))

	if(opacity)
		directional_opacity = ALL_CARDINALS

	//Pathfinding related
	if(movement_cost && path_weight == 1) // This updates pathweight automatically. //
		path_weight = movement_cost

	// GetAbove()/GetBelow() inlined: src is already the turf, and most z-levels have no neighbour.
	if(HasAbove(z))
		var/turf/Ab = get_step(src, UP)
		Ab?.multiz_turf_new(src, DOWN)
	if(HasBelow(z))
		var/turf/Be = get_step(src, DOWN)
		Be?.multiz_turf_new(src, UP)

	if(uses_integrity)
		atom_integrity = max_integrity

REGISTRY_MEMBERSHIP(/turf, REGISTRY_CLEANBOT_RESERVED_TURFS)

/turf
	destroy_hint = QDEL_HINT_IWILLGC

/turf/on_destroy(force)
	if (!changing_turf)
		stack_trace("Improper turf qdel. Do not qdel turfs directly.")
	changing_turf = FALSE
	// Rust owns turf adjacency; /turf/open/on_destroy's unregister drops it.
	..()

/turf/lifecycle_dematerialize()
	..()
	registry_leave(REGISTRY_CLEANBOT_RESERVED_TURFS, src)

/// Explosion entry point: every turf is a sink of the blast packet (damage.md §3, D-turf).
/// Turfs that change turf instead of losing integrity override receive_explosion().
/turf/ex_act(severity)
	return receive_explosion(severity)

/turf/proc/is_space()
	return 0

/turf/proc/is_intact()
	return 0

// Used by shuttle code to check if this turf is empty enough to not crush want it lands on.
/turf/proc/is_solid_structure()
	return 1

CAPABILITIES(/turf)
	op("turf_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 10), then(PROC_REF(turf_item_op)))
	op("turf_touch", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 10), label("Touch"), then(PROC_REF(turf_touch_op)))
	op("turf_crawl", item(/atom/movable), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 10), label("Crawl"), then(PROC_REF(turf_drag)))

/// The touch op: the old attack_hand.
/turf/proc/turf_touch_op(datum/act/op/A)
	return turf_hand(A.actor, null, null) ? OP_OK : OP_DECLINE

/// The item op: the old attackby.
/turf/proc/turf_item_op(datum/act/op/A)
	return turf_item(A.actor, A.held) ? OP_OK : OP_DECLINE

/// Old attack_hand: toggle a door on the tile, or pull what you're pulling onto it. FALSE when neither. (Also called by name by what touches a tile for another.)
/turf/proc/turf_hand(mob/user, obj/item/held, datum/interaction/interaction)
	//QOL feature, clicking on turf can toggle doors, unless pulling something
	if(!user?.pulling_target())
		var/obj/machinery/door/airlock/AL = locate_on(src, /obj/machinery/door/airlock)
		if(AL)
			AL.attack_hand(user)
			return TRUE
		var/obj/machinery/door/firedoor/FD = locate_on(src, /obj/machinery/door/firedoor)
		if(FD)
			FD.attack_hand(user)
			return TRUE

	var/atom/movable/pulling = user?.pulling_target()
	if(!(user.canmove) || user.restrained() || !pulling)
		return 0
	if(pulling.anchored || !isturf(pulling.loc))
		return 0
	if(pulling.loc != user.loc && get_dist(user, pulling) > 1)
		return 0
	if(ismob(pulling))
		var/mob/M = pulling
		var/atom/movable/t = M?.pulling_target()
		M.stop_pulling()
		step(pulling, get_dir(pulling.loc, src))
		M.start_pulling(t)
	else
		step(pulling, get_dir(pulling.loc, src))
	return 1

/// Old attackby: dig the tile with a shovel; a pickup-mode bag collects the tile. Otherwise falls through.
/turf/proc/turf_item(mob/user, obj/item/W)
	// Check if this turf can be dug up, check initial because we remove the flag when we've exhausted all loot, but still want to keep dig functionality
	if((flags & TURF_CAN_DIG_SHOVEL) && !density && istype(W, /obj/item/shovel))
		handle_turf_dig(user, W)
		return TRUE
	// Collect objects on turf if the bag supports scooping stuff up
	if(istype(W, /obj/item/storage))
		var/obj/item/storage/S = W
		if(S.use_to_pickup && S.collection_mode)
			S.gather_all(src, user)
	return FALSE

/turf
	silicon_use = ROBOT_USE_HAND

// Hits a mob on the tile.
/turf/proc/attack_tile(obj/item/W, mob/living/user)
	if(!istype(W))
		return FALSE

	var/list/viable_targets = list()
	var/success = FALSE // Hitting something makes this true. If its still false, the miss sound is played.

	for(var/mob/living/L in contents)
		if(L == user) // Don't hit ourselves.
			continue
		viable_targets += L

	if(!viable_targets.len) // No valid targets on this tile.
		if(W.can_cleave)
			success = W.cleave(user, src)
	else
		var/mob/living/victim = pick(viable_targets)
		success = W.resolve_attackby(victim, user)

	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src, no_attack_icons = TRUE)

	if(!success) // Nothing got hit.
		act_message(user, src, others = span_warning("%U% swipes %I% over %T%."), item = W)
		play_sfx(src, SFX_WEAPONS_PUNCHMISS)
	return success

/// Old MouseDrop_T: a lying mob crawls, dragging something along onto the tile.
/turf/proc/turf_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/O = A.held
	var/turf/T = get_turf(user)
	var/area/area = T.loc
	if((istype(area) && !(area.get_gravity())) || (istype(T,/turf/space)))
		return OP_DECLINE
	if(istype(O, /atom/movable/screen))
		return OP_DECLINE
	if(user.restrained() || user.stat || user.has_status(STAT_STUNNED) || user.has_status(STAT_PARALYZED) || (!user.lying && !istype(user, /mob/living/silicon/robot)) || LAZYLEN(user?.grabbed_by_list()) || user.is_paralyzed())
		return OP_DECLINE
	if((!(istype(O, /atom/movable)) || O.anchored || !Adjacent(user) || !Adjacent(O) || !user.Adjacent(O)))
		return OP_DECLINE
	if(!isturf(O.loc) || !isturf(user.loc))
		return OP_DECLINE
	if(isanimal(user) && O != user)
		return OP_DECLINE
	task_timed(user, 25 + (5 * user.status_units(STAT_WEAKENED)), O, src, PROC_REF(crawl_drag_done), list(O, user))
	return OP_OK

/turf/proc/crawl_drag_done(atom/movable/O, mob/user)
	if(user.stat)
		return
	step_towards(O, src)
	if(ismob(O))
		// The wiggle is one chained animation; the transform settles once it has played.
		animate(O, transform = turn(O.transform, 20), time = 2)
		animate(transform = turn(O.transform, -20), time = 4)
		animate(transform = O.transform, time = 2)
		after(O, 0.8 SECONDS, TYPE_PROC_REF(/atom/movable, update_transform))

/turf/CanPass(atom/movable/mover, turf/target)
	if(!target)
		return FALSE

	if(istype(mover)) // turf/Enter(...) will perform more advanced checks
		return !density

	stack_trace("Non movable passed to turf CanPass : [mover]")
	return FALSE

//There's a lot of QDELETED() calls here if someone can figure out how to optimize this but not runtime when something gets deleted by a Bump/CanPass/Cross call, lemme know or go ahead and fix this mess - kevinz000
/turf/Enter(atom/movable/mover, atom/oldloc)
	// Do not call ..()
	// Byond's default turf/Enter() doesn't have the behaviour we want with Bump()
	// By default byond will call Bump() on the first dense object in contents
	// Here's hoping it doesn't stay like this for years before we finish conversion to step_
	var/atom/firstbump
	var/CanPassSelf = CanPass(mover, src)
	if(CanPassSelf || CHECK_BITFIELD(mover.movement_type, UNSTOPPABLE))
		for(var/i in contents)
			if(QDELETED(mover))
				return FALSE		//We were deleted, do not attempt to proceed with movement.
			if(i == mover || i == mover.loc) // Multi tile objects and moving out of other objects
				continue
			var/atom/movable/thing = i
			if(!thing.Cross(mover))
				if(QDELETED(mover))		//Mover deleted from Cross/CanPass, do not proceed.
					return FALSE
				if(CHECK_BITFIELD(mover.movement_type, UNSTOPPABLE))
					mover.Bump(thing)
					continue
				else
					if(!firstbump || ((thing.layer > firstbump.layer || thing.flags & ON_BORDER) && !(firstbump.flags & ON_BORDER)))
						firstbump = thing
	if(QDELETED(mover))					//Mover deleted from Cross/CanPass/Bump, do not proceed.
		return FALSE
	if(!CanPassSelf)	//Even if mover is unstoppable they need to bump us.
		firstbump = src
	if(firstbump)
		mover.Bump(firstbump)
		return !QDELETED(mover) && CHECK_BITFIELD(mover.movement_type, UNSTOPPABLE)
	return TRUE

/turf/Exit(atom/movable/mover, atom/newloc)
	. = ..()
	if(!. || QDELETED(mover))
		return FALSE
	for(var/i in contents)
		if(i == mover)
			continue
		var/atom/movable/thing = i
		if(!thing.Uncross(mover, newloc))
			if(thing.flags & ON_BORDER)
				mover.Bump(thing)
			if(!CHECK_BITFIELD(mover.movement_type, UNSTOPPABLE))
				return FALSE
		if(QDELETED(mover))
			return FALSE		//We were deleted.

/turf/proc/is_plating()
	return 0

/turf/proc/levelupdate()
	for(var/obj/O in turf_contents_of_type(src, /obj))
		O.hide(O.hides_under_flooring() && !is_plating())

/turf/proc/AdjacentTurfs(check_blockage = TRUE)
	. = list()
	for(var/turf/T as anything in (trange(1,src) - src))
		if(check_blockage)
			if(!T.density)
				if(!LinkBlocked(src, T) && !TurfBlockedNonWindow(T))
					. += T
		else
			. += T

/turf/proc/CardinalTurfs(check_blockage = TRUE)
	. = list()
	for(var/turf/T as anything in AdjacentTurfs(check_blockage))
		if(T.x == src.x || T.y == src.y)
			. += T

/turf/proc/Distance(turf/t)
	if(get_dist(src,t) == 1)
		var/cost = (src.x - t.x) * (src.x - t.x) + (src.y - t.y) * (src.y - t.y)
		cost *= ((isnull(path_weight)? slowdown : path_weight) + (isnull(t.path_weight)? t.slowdown : t.path_weight))/2
		return cost
	else
		return get_dist(src,t)

/turf/proc/AdjacentTurfsSpace()
	var/L[] = new()
	for(var/turf/t in oview(src,1))
		if(!t.density)
			if(!LinkBlocked(src, t) && !TurfBlockedNonWindow(t))
				L.Add(t)
	return L

/turf/proc/contains_dense_objects()
	if(density)
		return 1
	for(var/atom/A in turf_contents_of_type(src, /atom))
		if(A.density && !(A.flags & ON_BORDER))
			return 1
	return 0

/turf/proc/update_blood_overlays()
	return

// Called when turf is hit by a thrown object
/turf/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	if(!density)
		return

	if(!get_gravity(source)) //Checked a different codebase for reference. Turns out it's only supposed to happen in no-gravity
		after(source, 0.2 SECONDS, TYPE_PROC_REF(/atom/movable, om_step), with = list(turn(source.last_move, 180))) //This makes it float away after hitting a wall in 0G
	if(isliving(source))
		var/mob/living/M = source
		M.turf_collision(src, throwingdatum?.speed)

/turf/AllowDrop()
	return TRUE

/turf/proc/can_engrave()
	return FALSE

/turf/proc/try_graffiti(mob/vandal, obj/item/tool, click_parameters)

	if(!tool || !tool.sharp || !can_engrave())
		return FALSE

	if(jobban_isbanned(vandal, JOB_GRAFFITI))
		to_chat(vandal, span_warning("You are banned from leaving persistent information across rounds."))
		return

	var/too_much_graffiti = 0
	for(var/obj/effect/decal/writing/W in turf_contents_of_type(src, /obj/effect/decal/writing))
		too_much_graffiti++
	if(too_much_graffiti >= 5)
		to_chat(vandal, span_warning("There's too much graffiti here to add more."))
		return FALSE

	open_request(src, /datum/prompt/text/graffiti, PROC_REF(graffiti_entered), answerer = vandal, subject = tool, click_parameters = click_parameters)
	return TRUE

/// Engraving with a tool (the subject, held throughout) next to the turf.
/datum/prompt/text/graffiti
	title = "Graffiti"
	question = "Enter a message to engrave."
	default = ""
	max_len = MAX_MESSAGE_LEN
	timeout = 0
	recheck_on_open = TRUE
	ask_flags = ASK_HELD | ASK_CAPABLE
	var/click_parameters

/datum/prompt/text/graffiti/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/graffiti/recheck_extra()
	var/mob/vandal = answerer
	var/turf/wall = owner
	var/obj/item/tool = subject
	if(!istype(vandal) || QDELETED(vandal) || !istype(wall) || QDELETED(wall) || !istype(tool) || QDELETED(tool))
		return "gone"
	return wall.Adjacent(vandal) ? null : "too far away"

/turf/proc/graffiti_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/graffiti/ask = context.answer
	var/mob/vandal = ask.answerer
	var/message = ask.value
	act_message(vandal, src, others = span_warning("%U% begins carving something into %T%."))
	task_start(/datum/task/timed/turf_graffiti, vandal, src, duration = max(2 SECONDS, length(message)), message = message, click_parameters = ask.click_parameters)
	return TRUE

/datum/task/timed/turf_graffiti
	complete_proc = /turf/proc/graffiti_done
	var/message
	var/click_parameters

/turf/proc/graffiti_done(datum/task/timed/turf_graffiti/task)
	var/mob/vandal = task.actor
	var/message = task.message
	var/click_parameters = task.click_parameters
	act_message(vandal, src, others = span_danger("%U% carves some graffiti into %T%."))
	var/obj/effect/decal/writing/graffiti = new(src)
	graffiti.message = message
	graffiti.author = vandal.ckey

	if(click_parameters)
		var/list/mouse_control = params2list(click_parameters)
		var/p_x = 0
		var/p_y = 0
		if(mouse_control["icon-x"])
			p_x = text2num(mouse_control["icon-x"]) - 16
		if(mouse_control["icon-y"])
			p_y = text2num(mouse_control["icon-y"]) - 16

		graffiti.pixel_x = p_x
		graffiti.pixel_y = p_y

	if(lowertext(message) == "elbereth")
		to_chat(vandal, span_notice("You feel much safer."))

// Returns false if stepping into a tile would cause harm (e.g. open space while unable to fly, water tile while a slime, lava, etc).
/turf/proc/is_safe_to_enter(mob/living/L)
	if(LAZYLEN(dangerous_objects))
		for(var/obj/O in dangerous_objects)
			if(!O.is_safe_to_step(L))
				return FALSE
	return TRUE

// Tells the turf that it currently contains something that automated movement should consider if planning to enter the tile.
// This uses lazy list macros to reduce memory footprint, since for 99% of turfs the list would've been empty anyways.
/turf/proc/register_dangerous_object(obj/O)
	if(!istype(O))
		return FALSE
	LAZYADD(dangerous_objects, O)

// Similar to above, for when the dangerous object stops being dangerous/gets deleted/moved/etc.
/turf/proc/unregister_dangerous_object(obj/O)
	if(!istype(O))
		return FALSE
	LAZYREMOVE(dangerous_objects, O)
	UNSETEMPTY(dangerous_objects) // This nulls the list var if it's empty.

/turf/occult_act(mob/living/user)
	to_chat(user, span_cult("You consecrate the floor."))
	ChangeTurf(/turf/simulated/floor/cult, preserve_outdoors = TRUE)
	return TRUE

// We're about to be the A-side in a turf translation
/turf/proc/pre_translate_A(turf/B)
	return
// We're about to be the B-side in a turf translation
/turf/proc/pre_translate_B(turf/A)
	return
// We were the the A-side in a turf translation
/turf/proc/post_translate_A(turf/B)
	return
// We were the the B-side in a turf translation
/turf/proc/post_translate_B(turf/A)
	return

/turf/proc/add_vomit_floor(mob/living/M, toxvomit = NONE, purge = TRUE)

	var/obj/effect/decal/cleanable/vomit/V = new /obj/effect/decal/cleanable/vomit(src, contagion_copies(M.get_spreadable_contagions()))

	if (QDELETED(V))
		V = locate_within(src, /obj/effect/decal/cleanable/vomit)
	if(!V)
		return
	if(toxvomit == VOMIT_PURPLE)
		V.icon_state = "vomitpurp_1"
		V.random_icon_states = list("vomitpurp_1", "vomitpurp_2", "vomitpurp_3", "vomitpurp_4")
	else if (toxvomit == VOMIT_TOXIC)
		V.icon_state = "vomittox_1"
		V.random_icon_states = list("vomittox_1", "vomittox_2", "vomittox_3", "vomittox_4")
	else if (toxvomit == VOMIT_NANITE)
		V.name = "metallic slurry"
		V.desc = "A puddle of metallic slury that looks vaguely like very fine sand. It almost seems like it's moving..."
		V.icon_state = "vomitnanite_1"
		V.random_icon_states = list("vomitnanite_1", "vomitnanite_2", "vomitnanite_3", "vomitnanite_4")
	if(purge && ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.ingested)
			clear_reagents_to_vomit_pool(H, V)

/proc/clear_reagents_to_vomit_pool(mob/living/carbon/human/H, obj/effect/decal/cleanable/vomit/V)
	H.ingested.trans_to(V, H.ingested.total_volume / 10)
	for(var/datum/reagent/R in H.ingested.reagent_list)
		H.ingested.remove_reagent(R, min(R.volume, 10))

/**
* 	Called when this turf is being washed. Washing a turf will also wash any mopable floor decals
*/
/turf/wash(clean_types)
	. = ..()

	if(istype(src, /turf/simulated))
		var/turf/simulated/T = src
		T.dirt = 0

	for(var/am in contents_of(src))
		if(am == src)
			continue
		var/atom/movable/movable_content = am
		if(!ismopable(movable_content))
			continue
		movable_content.wash(clean_types)

/// Used during turf_cascade subsystem to determine additional effects when spreading, and directions it may spread
/turf/proc/conversion_cascade_act(list/already_marked_turfs)
	var/list/expanding_turfs = list()

	for(var/expand_dir in GLOB.cardinalz)
		var/turf/next_turf = get_step(src, expand_dir)
		if(next_turf && next_turf.type != type && !(next_turf in already_marked_turfs)) // Yes in already_marked_turfs is expensive, but less expensive than 6 dupes per turf potentially in the loop
			expanding_turfs += next_turf

	return expanding_turfs
