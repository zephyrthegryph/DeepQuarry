/// An ongoing slide across a slippery floor. (Was /datum/component/turfslip; now a plain datum
/// owned by the sliding mob, /mob/living var turfslip.)
/datum/turfslip
	/// The sliding mob.
	var/mob/living/owner
	var/slipping_dir = null
	var/slip_dist = 1
	var/dirtslip = FALSE

/// Owned: the slide in progress, if any.
/mob/living/var/datum/turfslip/turfslip


/datum/turfslip/New(mob/living/new_owner)
	..()
	rel_set(src, nameof(owner), new_owner)
	slipping_dir = owner.dir
	observe(owner, /datum/notice/moved, src, then(PROC_REF(move_react)))

/// The mob's slide, starting one if it has none (was LoadComponent).
/mob/living/proc/get_or_start_turfslip() as /datum/turfslip
	if(!turfslip)
		rel_set(src, nameof(turfslip), new /datum/turfslip(src))
	return turfslip

/// Ends the slide: detaches from the mob and deletes this datum (was qdel(src) on the component).
/datum/turfslip/proc/end_slip()
	if(owner?.turfslip == src)
		rel_take(owner, nameof(owner.turfslip))
	spent(src)

/datum/turfslip/proc/start_slip(turf/simulated/start, is_dirt)
	var/slip_stun = 6
	var/floor_type = "wet"
	var/already_slipping = (slip_dist > 1)

	// Handle dirt slipping
	dirtslip = is_dirt
	if(dirtslip)
		slip_stun = 10
		if(start.dirt > 50)
			floor_type = "dirty"
		else if(start.is_outdoors())
			floor_type = "uneven"

	// Unlucky behavior
	if(has_trait(owner, TRAIT_UNLUCKY) && start.wet)
		slip_dist = rand(5,9) // Random longer distances on slip
		slip_stun = 10
		dirtslip = FALSE

	else
		// Proper sliding behavior
		switch(start.wet)
			if(TURFSLIP_WET)
				// Slipping on wet turf doesn't push you a turf
				owner.slip("the [floor_type] floor", slip_stun)
				end_slip()
				return

			if(TURFSLIP_LUBE)
				floor_type = "slippery"
				slip_dist = 99 //Skill issue.
				slip_stun = 10
				dirtslip = FALSE

			if(TURFSLIP_ICE)
				floor_type = "icy"
				slip_dist = 99 //Eternal slip for ice puzzles
				slip_stun = 4
				dirtslip = FALSE

	// Only start the slip timer if we are not already sliding
	if(!already_slipping)
		owner.slip("the [floor_type] floor", slip_stun)
		after(src, 0.1 SECONDS, PROC_REF(next_slip))

/datum/turfslip/proc/move_react(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)

	// Can the mob slip?
	if(QDELETED(owner) || !isturf(owner.loc))
		end_slip()
		return

	// Can the turf be slipped on?
	var/turf/simulated/ground = get_turf(owner)
	if(!ground)
		end_slip()
		return
	if(!ground.check_slipping(owner,dirtslip))
		// End our slip if we have no more slip remaining
		if(slip_dist <= 0)
			end_slip()
			return
		// reduce absurd slip distances to something reasonable if we are no longer standing on lube
		if(slip_dist > 4)
			slip_dist = 4

	else if(ground.wet >= TURFSLIP_LUBE) // Lube and above slips forever
		// Lube slips forever, if we re-enter the lube then restore our slip
		slip_dist = 99

	after(src, 0.1 SECONDS, PROC_REF(next_slip))

/datum/turfslip/proc/next_slip()
	// check tile for next slip
	owner.is_slipping = TRUE
	if(!step(owner, slipping_dir) || dirtslip) // done sliding, failed to move, dirt also only slips once
		slip_dist = 0
		end_slip()
		return
	// Kill the slip if it's over
	if(!--slip_dist)
		end_slip()
		return

// the slipping mob stops sliding.
/datum/turfslip/lifecycle_prerelease()
	..()
	if(owner)
		owner.inertia_dir = 0
		owner.is_slipping = FALSE

////////////////////////////////////////////////////////////////////////////////////////
// Helper proc
////////////////////////////////////////////////////////////////////////////////////////
/turf/proc/check_slipping(mob/living/M,dirtslip)
	return FALSE

/turf/simulated/check_slipping(mob/living/M,dirtslip)
	if(M?.buckled_to())
		return FALSE
	if(M.is_incorporeal()) // Mar!
		return FALSE
	if(ishuman(M))
		var/mob/living/carbon/human/humie = M
		if(humie.get_equipped_item(SLOT_ID_SHOES) && (humie.get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP)) // Includes activated magboots too
			return FALSE
		if(humie.species && (humie.species.flags & NO_SLIP))
			return FALSE
	if(isanimal(M)) // Simplemobs have their own slip logic
		var/mob/living/simple_mob/simple = M
		return simple.animal_slip(wet, dirtslip)
	if(!wet && !(dirtslip && (dirt > 50 || is_outdoors() == OUTDOORS_YES)))
		return FALSE
	if(wet == TURFSLIP_WET && M.m_intent == I_WALK)
		return FALSE
	return TRUE

