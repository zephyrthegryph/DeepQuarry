//////////////////////////////
// Tracks mining zone progress and decay
// Makes mining zones more difficult as you enter new ones
// THIS IS THE FIRST UNIT INITIALIZED THAT STARTS EVERYTHING
//////////////////////////////
GLOBAL_DATUM(rm_controller, /datum/controller/rogue)

/datum/controller/rogue
	var/list/datum/rogue/zonemaster/all_zones
	var/list/datum/rogue/zonemaster/clean_zones
	var/list/datum/rogue/zonemaster/ready_zones

	//So I don't have to do absurd list[list[thing]] over and over.
	var/static/list/diffstep_nums = list(
		100,
		350,
		600,
		900,
		1250,
		1700)

	var/static/list/diffstep_chances = list(
		10,
		20,
		30,
		45,
		60,
		80)

	var/static/list/diffstep_strs = list(
		"Low",
		"Moderate",
		"High",
		"Very High",
		"Extreme",
		"ERROR!!@MEM:CH@05R31GN5")

	//The ever-changing difficulty
	var/difficulty = 100

	//Info about our current step
	var/diffstep = 1

	//Difficulty cap
	var/max_diffstep = 6

	//The current mining zone that the shuttle goes to and whatnot
	var/tmp/datum/rogue/zonemaster/current_zone
	var/tmp/datum/rogue/zonemaster/previous_zone

	// The world.time at which the scanner was last run (for cooldown)
	EXPIRY_DECLARE(last_scan)
	var/scan_wait = 5 //In minutes

	var/debugging = 0

	///// Prefab Asteroids /////
	var/prefabs = list(
		"tier1" = list(/datum/rogue/asteroid/predef/cargo),
		"tier2" = list(/datum/rogue/asteroid/predef/cargo,/datum/rogue/asteroid/predef/cargo/angry),
		"tier3" = list(/datum/rogue/asteroid/predef/cargo,/datum/rogue/asteroid/predef/cargo/angry),
		"tier4" = list(/datum/rogue/asteroid/predef/cargo,/datum/rogue/asteroid/predef/cargo/angry,/datum/rogue/asteroid/predef/cargo_large),
		"tier5" = list(/datum/rogue/asteroid/predef/cargo/angry,/datum/rogue/asteroid/predef/cargo_large),
		"tier6" = list(/datum/rogue/asteroid/predef/cargo/angry,/datum/rogue/asteroid/predef/cargo_large)
	)

	///// Monster Lists /////
	var/mobs = list(
		"tier1" = list(
						/mob/living/simple_mob/animal/space/bats/roguemines = 3,
						/mob/living/simple_mob/animal/space/carp/roguemines = 2,
						/mob/living/simple_mob/animal/space/goose/roguemines = 1),

		"tier2" = list(
						/mob/living/simple_mob/animal/space/bats/roguemines = 1,
						/mob/living/simple_mob/animal/space/carp/roguemines = 2,
						/mob/living/simple_mob/animal/space/goose/roguemines = 2,
						/mob/living/simple_mob/vore/wolf/space/roguemines = 1),

		"tier3" = list(
						/mob/living/simple_mob/animal/space/carp/roguemines = 1,
						/mob/living/simple_mob/animal/space/goose/roguemines = 1,
						/mob/living/simple_mob/vore/wolf/space/roguemines = 3,
						/mob/living/simple_mob/animal/space/carp/large/roguemines = 2,
						/mob/living/simple_mob/animal/space/bear/roguemines = 1),

		"tier4" = list(
						/mob/living/simple_mob/vore/wolf/space/roguemines = 1,
						/mob/living/simple_mob/animal/space/carp/large/roguemines = 4,
						/mob/living/simple_mob/animal/space/bear/roguemines = 2),

		"tier5" = list(
						/mob/living/simple_mob/animal/space/carp/large/roguemines = 2,
						/mob/living/simple_mob/animal/space/bear/roguemines = 4,
						/mob/living/simple_mob/vore/aggressive/corrupthound/space/roguemines = 1),

		"tier6" = list(
						/mob/living/simple_mob/animal/space/bear/roguemines = 6,
						/mob/living/simple_mob/vore/aggressive/corrupthound/space/roguemines = 4,
						/mob/living/simple_mob/animal/space/carp/large/huge/roguemines = 1)
	)

CAPABILITIES(/datum/controller/rogue)
	owns_many(nameof(all_zones), /datum/rogue/zonemaster)
	owns_many(nameof(clean_zones), /datum/rogue/zonemaster)
	owns_many(nameof(ready_zones), /datum/rogue/zonemaster)

/// Difficulty decays every RM_DIFF_DECAY_TIME while set (the every() below).
/datum/controller/rogue/var/decaying = FALSE
TRACKED(/datum/controller/rogue, decaying)

/datum/controller/rogue/reactions()
	. = ..()
	. += every(RM_DIFF_DECAY_TIME, PROC_REF(decay), when = nameof(decaying))

/datum/controller/rogue/New()
	..()
	lifecycle_decls_init(src) // starts the declaration (a non-atom has no materialize)
	//How many zones are we working with here
	for(var/area/asteroid/rogue/A in world)
		rel_add(src, nameof(all_zones), new /datum/rogue/zonemaster(A))
	//set_decaying(TRUE) //Decay removed for now, since people aren't getting high scores as it is.

/// One difficulty decay (the every() while decaying; may also be called by hand).
/datum/controller/rogue/proc/decay(dt)
	log_world("RM(stats): DECAY on controller from [difficulty] to [difficulty+(RM_DIFF_DECAY_AMT)] min 100.") //DEBUG code for playtest stats gathering.
	adjust_difficulty(RM_DIFF_DECAY_AMT)

/datum/controller/rogue/proc/dbg(message)
	ASSERT(message) //I want a stack trace if there's no message
	if(debugging)
		log_world("[message]")

/datum/controller/rogue/proc/adjust_difficulty(amt)
	ASSERT(amt)

	difficulty = max(difficulty+amt, diffstep_nums[1]) //Can't drop below the lowest level.

	if(difficulty < diffstep_nums[diffstep])
		diffstep--
	else if(diffstep < max_diffstep)
		if(difficulty >= diffstep_nums[diffstep+1])
			diffstep++

/datum/controller/rogue/proc/get_oldest_zone()
	var/oldest_time = world.time
	var/oldest_zone

	for(var/datum/rogue/zonemaster/ZM in ready_zones)
		if(ZM.prepared_at < oldest_time) //Check ready so we don't return zones that ARE cleaning
			oldest_zone = ZM
			oldest_time = ZM.prepared_at

	return oldest_zone

/datum/controller/rogue/proc/mark_clean(datum/rogue/zonemaster/ZM)
	if(!(ZM in all_zones)) //What? Who?
		GLOB.rm_controller.dbg("RMC(mc): Some unknown zone asked to be listed.")

	if(ZM in ready_zones)
		GLOB.rm_controller.dbg("RMC(mc): Finite state machine broken.")

	rel_add(src, nameof(clean_zones), ZM)

/datum/controller/rogue/proc/mark_ready(datum/rogue/zonemaster/ZM)
	if(!(ZM in all_zones)) //What? Who?
		GLOB.rm_controller.dbg("RMC(mr): Some unknown zone asked to be listed.")

	if(ZM in clean_zones)
		GLOB.rm_controller.dbg("RMC(mr): Finite state machine broken.")

	rel_add(src, nameof(ready_zones), ZM)

/datum/controller/rogue/proc/unmark_clean(datum/rogue/zonemaster/ZM)
	if(!(ZM in all_zones)) //What? Who?
		GLOB.rm_controller.dbg("RMC(umc): Some unknown zone asked to be listed.")

	if(!(ZM in clean_zones))
		GLOB.rm_controller.dbg("RMC(umc): Finite state machine broken.")

	own_take_member(src, nameof(clean_zones), ZM)

/datum/controller/rogue/proc/unmark_ready(datum/rogue/zonemaster/ZM)
	if(!(ZM in all_zones)) //What? Who?
		GLOB.rm_controller.dbg("RMC(umr): Some unknown zone asked to be listed.")

	if(!(ZM in ready_zones))
		GLOB.rm_controller.dbg("RMC(umr): Finite state machine broken.")

	own_take_member(src, nameof(ready_zones), ZM)

/datum/controller/rogue/proc/prepare_new_zone()
	var/datum/rogue/zonemaster/ZM_target

	if(length(clean_zones))
		ZM_target = DEFAULTPICK(clean_zones, null)

	if(ZM_target)
		log_world("RM(stats): SCORING [length(ready_zones)] zones (if unscored).") //DEBUG code for playtest stats gathering.
		for(var/datum/rogue/zonemaster/ZM_toscore in ready_zones) //Score all the zones first.
			if(ZM_toscore.scored) continue
			ZM_toscore.score_zone()
		ZM_target.prepare_zone()
	else
		GLOB.rm_controller.dbg("RMC(pnz): I was asked for a new zone but there's no space.")

	if(length(clean_zones) <= 1) //Need to clean the oldest one, too.
		GLOB.rm_controller.dbg("RMC(pnz): Cleaning up oldest zone.")
		spawn(0) //Detatch it so we can return the new zone for now. // ALLOW(scheduler): clean_zone() sleeps between deletions: a long loop that has to yield to the tick
			var/datum/rogue/zonemaster/ZM_oldest = get_oldest_zone()
			if(ZM_oldest) ZM_oldest.clean_zone()

	return ZM_target

/// Accessor for the current_zone var.
/datum/controller/rogue/proc/current_zone() as /datum/rogue/zonemaster
	return current_zone

/// Accessor for the previous_zone var.
/datum/controller/rogue/proc/previous_zone() as /datum/rogue/zonemaster
	return previous_zone

