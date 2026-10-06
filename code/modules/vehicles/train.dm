/obj/vehicle/train
	name = "train"
	dir = 4

	move_delay = 1

	max_integrity = 100
	fire_dam_coeff = 0.7
	brute_dam_coeff = 0.5

	var/passenger_allowed = 1

	var/active_engines = 0
	var/train_length = 0
	var/latch_on_start = 1

	var/tmp/obj/vehicle/train/lead
	var/tmp/obj/vehicle/train/tow

	var/open_top = TRUE

//-------------------------------------------
// Standard procs
//-------------------------------------------
/obj/vehicle/train/Initialize(mapload)
	. = ..()
	for(var/obj/vehicle/train/T in orange(1, src))
		if(latch_on_start)
			latch(T, null)

/obj/vehicle/train/Move(atom/newloc, direct = 0, movetime)
	var/old_loc = get_turf(src)
	if((. = ..()))
		if(tow())
			tow().Move(old_loc)
	else if(lead())
		unattach()

/obj/vehicle/train/Bump(atom/Obstacle)
	if(istype(Obstacle,/obj/structure/stairs))
		return ..()
	if(!istype(Obstacle, /atom/movable))
		return
	var/atom/movable/A = Obstacle

	if(!A.anchored)
		var/turf/T = get_step(A, dir)
		if(isturf(T))
			A.Move(T)	//bump things away when hit

	if(emagged)
		if(isliving(A))
			var/mob/living/M = A
			visible_message(span_red("[src] knocks over [M]!"))
			M.apply_effects(5, 5)				//knock people down if you hit them
			M.injure(INJURY_BLUNT, 22 / move_delay, null, src)	// and do damage according to how fast the train is going
			if(ishuman(load))
				var/mob/living/D = load
				to_chat(D, span_red("You hit [M]!"))
				add_attack_logs(D,M,"Ran over with [src.name]")

//trains are commonly open topped, so there is a chance the projectile will hit the mob riding the train instead
/obj/vehicle/train/bullet_act(obj/item/projectile/Proj)
	if(has_buckled_mobs() && prob(70))
		var/mob/living/L = pick(src?.buckled_mob_list())
		L.bullet_act(Proj)
		return
	..()

APPEARANCE_TEMPLATE(/obj/vehicle/train, "{initial(icon_state)}{open?_open:}")

//-------------------------------------------
// Vehicle procs
//-------------------------------------------
/obj/vehicle/train/explode()
	if (tow())
		tow().unattach()
	unattach()
	..()


//-------------------------------------------
// Interaction procs
//-------------------------------------------
/obj/vehicle/train/relaymove(mob/user, direction)
	var/turf/T = get_step_to(src, get_step(src, direction))
	if(!T)
		to_chat(user, "You can't find a clear area to step onto.")
		return 0

	if(user != load)
		if(user?.loc == src)		//for handling players stuck in src - this shouldn't happen - but just in case it does
			user.forceMove(T)
			return 1
		return 0

	unload(user, direction)

	to_chat(user, span_blue("You climb down from [src]."))

	return 1

EXTEND_INTERACTIONS(/obj/vehicle/train, \
	INTERACT_DRAG("Load", PROC_REF(interaction_train_drag)), \
	INTERACT_HAND(null, PROC_REF(interaction_train_hand)), \
	INTERACT_VERB("Unlatch", PROC_REF(train_unlatch), REQ_ON(PRED_TARGET, /obj/vehicle/train/proc/pred_train_unlatchable, null)), \
)

/// Requirement for "Unlatch": unhitches this train from the one in front of it. Overridden FALSE where nothing latches.
/obj/vehicle/train/proc/pred_train_unlatchable(mob/actor, atom/target, obj/item/held)
	return TRUE

/// Old MouseDrop_T: drop a train car to latch it, anything else to load it.
/obj/vehicle/train/proc/interaction_train_drag(mob/user, atom/movable/C, datum/interaction/interaction)
	if(user?.buckled_to() || user.stat || user.restrained() || !Adjacent(user) || !user.Adjacent(C) || !istype(C) || (user == C && !user.canmove))
		return TRUE
	if(istype(C,/obj/vehicle/train))
		latch(C, user)
	else if(!load(C, user))
		to_chat(user, span_red("You were unable to load [C] on [src]."))
	return TRUE

/// Old attack_hand: climb on, or unload what's aboard.
/obj/vehicle/train/proc/interaction_train_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || user.restrained() || !Adjacent(user))
		return TRUE

	if(user != load && (user?.loc == src))
		user.forceMove(loc)			//for handling players stuck in src
	else if(load)
		unload(user)			//unload if loaded
	else if(!load && !user?.buckled_to())
		load(user, user)				//else try climbing on board
	return TRUE

/// Shared trolley step (security and rover trolleys): wirecutters on an open panel toggle the load limiter.
/obj/vehicle/train/proc/interaction_train_limiter_cable(mob/user, obj/item/W, datum/interaction/interaction)
	if(!open || !W.has_tool_quality(TOOL_WIRECUTTER))
		return FALSE
	passenger_allowed = !passenger_allowed
	act_message(user, src, MSG_SELF(span_notice("You [passenger_allowed ? "cut" : "mend"] the load limiter cable.")), \
		MSG_OTHERS(span_notice("%U% [passenger_allowed ? "cuts" : "mends"] a cable in %T%.")))
	return TRUE

/// Old verb "Unlatch".
/obj/vehicle/train/proc/train_unlatch(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user))
		return

	if(!user.canmove || user.stat || user.restrained() || !Adjacent(user))
		return

	unattach(user)


//-------------------------------------------
// Latching/unlatching procs
//-------------------------------------------

//attempts to attach src as a follower of the train T
//Note: there is a modified version of this in code\modules\vehicles\cargo_train.dm specifically for cargo train engines
/obj/vehicle/train/proc/attach_to(obj/vehicle/train/T, mob/user)
	if (get_dist(src, T) > 1)
		if(user)
			to_chat(user, span_red("[src] is too far away from [T] to hitch them together."))
		return

	if (lead())
		if(user)
			to_chat(user, span_red("[src] is already hitched to something."))
		return

	if (T.tow())
		if(user)
			to_chat(user, span_red("[T] is already towing something."))
		return

	//check for cycles.
	var/obj/vehicle/train/next_car = T
	while (next_car)
		if (next_car == src)
			if(user)
				to_chat(user, span_red("That seems very silly."))
			return
		next_car = next_car.lead()

	//latch with src as the follower
	rel_set(src, nameof(lead), T) // REL_PAIR: T's tow names us
	set_dir(lead().dir)

	if(user)
		to_chat(user, span_blue("You hitch [src] to [T]."))

	update_stats()


//detaches the train from whatever is towing it
/obj/vehicle/train/proc/unattach(mob/user)
	if (!lead())
		to_chat(user, span_red("[src] is not hitched to anything."))
		return

	var/obj/vehicle/train/old_lead = lead()
	rel_clear(src, nameof(lead)) // the pair: old_lead's tow clears too
	old_lead.update_stats()

	to_chat(user, span_blue("You unhitch [src] from [old_lead]."))

	update_stats()

/obj/vehicle/train/proc/latch(obj/vehicle/train/T, mob/user)
	if(!istype(T) || !Adjacent(T))
		return 0

	var/T_dir = get_dir(src, T)	//figure out where T is wrt src

	if(dir == T_dir) 	//if car is ahead
		src.attach_to(T, user)
	else if(reverse_direction(dir) == T_dir)	//else if car is behind
		T.attach_to(src, user)

//returns 1 if this is the lead car of the train
/obj/vehicle/train/proc/is_train_head()
	if (lead())
		return 0
	return 1

//-------------------------------------------------------
// Stat update procs
//
// Used for updating the stats for how long the train is.
// These are useful for calculating speed based on the
// size of the train, to limit super long trains.
//-------------------------------------------------------
/obj/vehicle/train/update_stats()
	//first, seek to the end of the train
	var/obj/vehicle/train/T = src
	while(T.tow())
		//check for cyclic train.
		if (T.tow() == src)
			var/obj/vehicle/train/old_lead = lead()
			rel_clear(src, nameof(lead)) // the pair: old_lead's tow clears too
			old_lead?.update_stats()
			update_stats()
			return
		T = T.tow()

	//now walk back to the front.
	var/active_engines = 0
	var/train_length = 0
	while(T)
		train_length++
		if (T.powered && T.on)
			active_engines++
		T.update_car(train_length, active_engines)
		T = T.lead()

/obj/vehicle/train/proc/update_car(train_length, active_engines)
	return

/// Accessor for the tow var.
/obj/vehicle/train/proc/tow() as /obj/vehicle/train
	return tow

/// Accessor for the lead var.
/obj/vehicle/train/proc/lead() as /obj/vehicle/train
	return lead

CAPABILITIES(/obj/vehicle/train)
	links(/obj/vehicle/train::lead, /obj/vehicle/train::tow)
