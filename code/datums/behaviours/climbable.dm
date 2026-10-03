/// Climbable behaviour (was /datum/element/climbable). Allows climbing an object using
/// mousedrag or a verb. A shared behaviour singleton: the per-object state (delay,
/// vaulting, who is climbing) lives on the object; variants are subtypes.
///
/// Attach with O.make_climbable(), detach with O.unmake_climbable(). Senders start a
/// climb with /datum/om/event/climb_start and shake climbers off with
/// /datum/om/event/climb_shake; moving the object (unforced) also shakes them.
/datum/om/behaviour/climbable
	handles = list(/datum/om/event/climb_start, /datum/om/event/climb_shake, /datum/om/event/moved, /datum/om/event/examine)

#define CLIMBABLE_TRAIT_SOURCE "climbable_behaviour"

/obj
	/// The climbable behaviour type attached by make_climbable(), or null.
	var/climbable_type
	/// Climb time for the climbable behaviour.
	var/climbable_delay = 3.5 SECONDS
	/// Railings: climbing from the object's own turf goes over it to the facing turf.
	var/climbable_vaulting = FALSE
	/// The mobs currently climbing this object: a relation list view (lazy).
	var/list/mob/living/climbers

/// Makes this object climbable with behaviour `kind` (a /datum/om/behaviour/climbable type).
/obj/proc/make_climbable(kind = /datum/om/behaviour/climbable, delay = 3.5 SECONDS, vaulting = FALSE)
	if(climbable_type)
		unmake_climbable()
	climbable_type = kind
	climbable_delay = delay
	climbable_vaulting = vaulting
	om_attach(src, kind)

/// Removes the climbable behaviour, if any.
/obj/proc/unmake_climbable()
	if(!climbable_type)
		return
	om_detach(src, climbable_type)
	climbable_type = null
	rel_clear(src, nameof(climbers))

/datum/om/behaviour/climbable/on_start(obj/O)
	grant(O, /obj/proc/climb_on, O)
	add_trait(O, TRAIT_CLIMBABLE, CLIMBABLE_TRAIT_SOURCE)

/datum/om/behaviour/climbable/on_stop(obj/O)
	revoke(O, /obj/proc/climb_on, O)
	remove_trait(O, TRAIT_CLIMBABLE, CLIMBABLE_TRAIT_SOURCE)
	rel_clear(O, nameof(/obj::climbers))

/datum/om/behaviour/climbable/on_climb_start(obj/O, datum/om/event/climb_start/event)
	var/mob/living/H = event.user
	if(istype(H) && can_climb(O, H))
		after(O, 0, TYPE_PROC_REF(/obj, climbable_do_climb), with = list(H)) // Out of the event delivery.

/datum/om/behaviour/climbable/on_climb_shake(obj/O, datum/om/event/climb_shake/event)
	shaken(O, event.user)

/datum/om/behaviour/climbable/on_moved(obj/O, datum/om/event/moved/event)
	if(!event.forced) // Don't perform this if going up stairs
		shaken(O, null)

/datum/om/behaviour/climbable/on_examine(obj/O, datum/om/event/examine/event)
	event.texts += span_notice("It looks climbable.")

/// The live climbers of `O` (a copy; dead climbers already left the view).
/datum/om/behaviour/climbable/proc/climbers_of(obj/O)
	return O.climbers ? O.climbers.Copy() : list()

/datum/om/behaviour/climbable/proc/add_climber(obj/O, mob/living/user)
	if(!QDELETED(user))
		rel_add(O, nameof(/obj::climbers), user)

/datum/om/behaviour/climbable/proc/remove_climber(obj/O, mob/living/user)
	rel_remove(O, nameof(/obj::climbers), user)

/// om_after() target: runs the climb on the object's current climbable behaviour.
/obj/proc/climbable_do_climb(mob/living/user)
	if(!climbable_type)
		return
	var/datum/om/behaviour/climbable/B = om_registry().behaviour(climbable_type)
	B.do_climb(src, user, climbable_delay)

/// Check if the mob is in any condition to climb the object, if the destination is blocked, and how to climb it
/datum/om/behaviour/climbable/proc/can_climb(obj/climbed_thing, mob/living/user, post_climb_check=0)
	if(user.is_incorporeal()) // No! Bad shadekin!
		return FALSE

	if (!can_touch(climbed_thing, user) || (!post_climb_check && (user in climbers_of(climbed_thing))))
		return FALSE

	if (!user.Adjacent(climbed_thing))
		to_chat(user, span_danger("You can't climb there, the way is blocked."))
		return FALSE

	var/obj/occupied = can_climb_turf(climbed_thing)
	if(occupied)
		to_chat(user, span_danger("There's \a [occupied] in the way."))
		return FALSE

	// Railings are a bit snowflakey, but needed for when you climb from their turf to their facing turf!
	if(climbed_thing.climbable_vaulting)
		if(get_turf(user) == get_turf(climbed_thing))
			occupied = can_climb_neighbor_turf(climbed_thing)
			if(occupied)
				to_chat(user, span_danger("You can't climb there, there's \a [occupied] in the way."))
				return FALSE
	return TRUE

/// Performs the wait and any remaining checks before the climb resolves.
/datum/om/behaviour/climbable/proc/do_climb(obj/climbed_thing, mob/living/user, delay_time)
	if(QDELETED(user) || QDELETED(climbed_thing))
		return

	act_message(user, climbed_thing, others = span_warning("%U% starts climbing onto %T%!"))
	add_climber(climbed_thing, user)
	om_task_start(/datum/om/task/timed/climbable_climb, user, user, duration = (issmall(user) ? delay_time * 0.6 : delay_time), climbed_thing = climbed_thing)

/datum/om/behaviour/climbable/proc/climb_ended(datum/om/task/timed/climbable_climb/task)
	var/obj/climbed_thing = task.climbed_thing
	var/mob/living/user = task.actor
	if(climbed_thing)
		remove_climber(climbed_thing, user)

/datum/om/task/timed/climbable_climb
	complete_proc = /datum/om/behaviour/climbable/proc/climb_done
	cancel_proc = /datum/om/behaviour/climbable/proc/climb_ended
	var/obj/climbed_thing

/datum/om/behaviour/climbable/proc/climb_done(datum/om/task/timed/climbable_climb/task)
	var/obj/climbed_thing = task.climbed_thing
	var/mob/living/user = task.actor
	if(!climbed_thing)
		return
	if(can_climb(climbed_thing, user, post_climb_check=1))
		climb_to(climbed_thing, user)
		if(get_turf(user) == get_turf(climbed_thing))
			act_message(user, climbed_thing, others = span_warning("%U% climbs onto %T%!"))
		else
			act_message(user, climbed_thing, others = span_warning("%U% climbed over %T%!"))
	else
		to_chat(user, span_warning("You fail to climb onto \the [climbed_thing]."))
	remove_climber(climbed_thing, user)

/// Resolve the climb by moving the mob to its final destination.
/datum/om/behaviour/climbable/proc/climb_to(obj/climbed_thing, mob/living/user)
	if(climbed_thing.climbable_vaulting && get_turf(user) == get_turf(climbed_thing))
		user.forceMove(get_step(climbed_thing, climbed_thing.dir))
	else
		user.forceMove(get_turf(climbed_thing))

/// Check if a mob is capable of climbing at all
/datum/om/behaviour/climbable/proc/can_touch(obj/climbed_thing, mob/user)
	if (!user)
		return 0
	if(!climbed_thing.Adjacent(user))
		return 0
	if (user.restrained() || user?.buckled_to())
		to_chat(user, span_notice("You need your hands and legs free for this."))
		return 0
	if (user.stat || user.has_status(EFFECT_PARALYZED) || user.has_status(EFFECT_SLEEPING) || user.lying || user.has_status(EFFECT_WEAKENED))
		return 0
	if (isAI(user))
		to_chat(user, span_notice("You need hands for this."))
		return 0
	return 1

/// Shakes an object, if anyone is climbing it, causes them to fall off it.
/datum/om/behaviour/climbable/proc/shaken(obj/climbed_thing, mob/user)
	var/list/climbers = climbers_of(climbed_thing)
	// You cannot shake yourself
	if(user) // Crates pass null on open because no user
		if(!LAZYLEN(climbers) || (user in climbers))
			return
		act_message(user, climbed_thing, MSG_SELF(span_notice("You shake %T%.")), MSG_OTHERS(span_warning("%U% shakes %T%.")))

	for(var/mob/living/M in climbers)
		if(M.is_incorporeal())
			continue
		if(M.lying) //No spamming this on people.
			continue
		if(M?.pulling_target() == climbed_thing) // Pulling stuff up stairs can get weird
			continue

		// Knock off climbers
		M.status_at_least(EFFECT_WEAKENED, 3)
		to_chat(M, span_danger("You topple as you are shaken off \the [climbed_thing]!"))
		remove_climber(climbed_thing, M)

		// Tumble down damage
		if(!prob(25))
			return

		// Apply damage to simple mobs, if human we go for specific limbs
		var/damage = rand(10,20)
		var/mob/living/carbon/human/H = M
		if(!istype(H))
			to_chat(H, span_danger("You land heavily!"))
			M.injure(INJURY_BLUNT, damage)
			continue

		// Try to hurt a specific limb
		var/obj/item/organ/external/affecting = H.get_organ(pick(BP_ALL))
		if(affecting)
			to_chat(M, span_danger("You land heavily on your [affecting.name]!"))
			H.injure(INJURY_BLUNT, damage, affecting.organ_tag)
			return

		// If no limb to hurt, just randomly apply damage
		to_chat(H, span_danger("You land heavily!"))
		H.injure(INJURY_BLUNT, damage)

// Cliff climbing requires climbing gear.
/datum/om/behaviour/climbable/cliff

/datum/om/behaviour/climbable/cliff/do_climb(obj/climbed_thing, mob/living/user, delay_time)
	// Special snowflake handling, because north facing cliffs require half the time
	var/obj/structure/cliff/C = climbed_thing
	if(C.is_double_cliff)
		delay_time /= 2
	. = ..(climbed_thing, user, delay_time)

/datum/om/behaviour/climbable/cliff/can_climb(obj/climbed_thing, mob/living/user, post_climb_check=0)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/clothing/shoes/shoes = H.get_equipped_item(SLOT_ID_SHOES)
		if(shoes && shoes.rock_climbing)
			return ..() // Do the other checks too.

	to_chat(user, span_warning("\The [climbed_thing] is too steep to climb unassisted."))
	return FALSE


// Breaks if climbed while unanchored, railings.
/datum/om/behaviour/climbable/unanchored_can_break

/datum/om/behaviour/climbable/unanchored_can_break/climb_to(obj/climbed_thing, mob/living/user)
	. = ..()
	if(!climbed_thing.anchored)
		climbed_thing.take_damage(9999, BRUTE, MELEE) // Fatboy, was originally maxhealth, but that var doesn't exist on everything


// Table flipping is important!
/datum/om/behaviour/climbable/table

/datum/om/behaviour/climbable/table/climb_to(obj/climbed_thing, mob/living/mover)
	var/obj/structure/table/TBL = climbed_thing
	if(TBL.flipped == 1 && mover.loc == TBL.loc)
		var/turf/T = get_step(climbed_thing, TBL.dir)
		if(T.Enter(mover))
			return T
	return ..()

#undef CLIMBABLE_TRAIT_SOURCE

/// Verb for climbing objects, emits the same event as mouse drop
/obj/proc/climb_on()
	set name = "Climb structure"
	set desc = "Climbs onto a structure."
	set category = VERB_CAT_OBJECT
	set src in oview(1)

	om_emit(src, new /datum/om/event/climb_start(usr))

/// Checks if something is blocking our climb destination, ignores climbable objects
/proc/can_climb_turf(obj/climbed_thing)
	READS_FROM() // what stands on a tile is asked when a choice is made, never cached
	var/turf/T = get_turf(climbed_thing)
	if(!T || !istype(T))
		return "empty void"
	if(T.density)
		return T
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(O && O.density && !(O.flags & ON_BORDER) && !has_trait(O,TRAIT_CLIMBABLE)) //ON_BORDER structures are handled by the Adjacent() check.
			return O
	return 0

/// Check if the destination turf for vaulting is blocked by something. Extremely similar to above.
/proc/can_climb_neighbor_turf(obj/climbed_thing)
	var/turf/T = get_step(climbed_thing, climbed_thing.dir)
	if(!T || !istype(T))
		return 0
	if(T.density == 1)
		return T
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(O && O.density && !(O.flags & ON_BORDER && !(turn(O.dir, 180) & climbed_thing.dir)) && !has_trait(O,TRAIT_CLIMBABLE))
			return O
	return 0

// ---------------------------------------------------------------- events

/// Notification: `user` tries to climb the object.
/datum/om/event/climb_start
	coalesce = FALSE
	/// The climbing mob.
	var/user

/datum/om/event/climb_start/New(user)
	src.user = user

/datum/om/event/climb_start/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_climb_start(E, src)

/datum/om/behaviour/proc/on_climb_start(datum/E, datum/om/event/climb_start/event)
	return

/// Notification: the object is shaken; climbers
/// fall off. `user` is who shook it, or null (a crate opening, a solar panel moving).
/datum/om/event/climb_shake
	coalesce = FALSE
	/// The shaking mob, or null.
	var/user

/datum/om/event/climb_shake/New(user)
	src.user = user

/datum/om/event/climb_shake/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_climb_shake(E, src)

/datum/om/behaviour/proc/on_climb_shake(datum/E, datum/om/event/climb_shake/event)
	return

/obj/relations()
	. = ..()
	. += rel_many(nameof(climbers))
