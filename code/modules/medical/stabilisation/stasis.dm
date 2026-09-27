// Stasis: buying time by suspending life processes (doc/health_system_review.md §5.5).
//
// Every stasis source (stasis bags, sleepers, cryopods, the mech sleeper, NIF
// emergency stasis, stasis cages, admin) is a /datum/modifier/stasis subtype that
// contributes BF_STASIS, a 0..1 share of life processes suspended (max rule).
//
// Each modifier inhibits the body's biology clock. Life samples elapsed local
// time once per frame, then runs biological work for each whole local cycle.
// A paused biological cycle skips:
//   - affliction ticks (progression, treatment, symptoms)     body.life_tick()
//   - metabolism and hunger                                    the chemicals system
//   - breathing (so oxygen debt stops accumulating)            the breathing system
//   - blood loss and regeneration                              the blood system
//   - the human live/dead segments (organs, defib timer, ...)  gate: human vitals
// Those read the paused flag through inStasisNow() / ctx.in_stasis(), never BF_STASIS.
// So at stasis 0.9 everything runs at 10% speed; at 1 it stops.

/datum/body
	/// Fractional remainder of a biological cycle, in nominal Life periods.
	var/tmp/stasis_clock = 0
	/// Last local biology time sampled by Life(), in deciseconds.
	var/tmp/stasis_last_virtual
	/// Whole local cycles due this frame, bounded before Life's catch-up pass.
	var/tmp/biology_due = 1
	/// TRUE when stasis paused the current Life() cycle.
	var/tmp/stasis_paused = FALSE

/// Consume local biology time since the previous Life frame. Nonbiological
/// systems still run on the real-time frame. Event wakes without elapsed local
/// time cannot advance biological processes in stasis.
/datum/body/proc/advance_stasis()
	var/domain = /datum/object_model/clock_domain/biology
	var/datum/object_model/clock_state/C = owner?.om_state?.clock_states?[domain]
	// Ordinary time needs no fractional bookkeeping. Faster local time is
	// consumed by Life's bounded biological-only catch-up pass.
	if(!C || C.rate == 1)
		stasis_clock = 0
		stasis_last_virtual = C?.settle()
		biology_due = 1
		stasis_paused = FALSE
		return FALSE
	if(C.rate <= 0)
		stasis_last_virtual = C.settle()
		biology_due = 0
		stasis_paused = TRUE
		return TRUE
	var/now = C.settle()
	if(isnull(stasis_last_virtual))
		stasis_last_virtual = now
	var/elapsed = max(0, now - stasis_last_virtual)
	stasis_last_virtual = now
	stasis_clock += elapsed / (LIFE_NOMINAL_SECONDS SECONDS)
	biology_due = min(LIFE_MAX_BIOLOGY_STEPS, floor(stasis_clock + 0.000001))
	// Keep at most one frame of debt. A long server stall cannot trigger
	// unbounded biological catch-up on a single mob.
	stasis_clock = min(LIFE_MAX_BIOLOGY_STEPS, max(0, stasis_clock - biology_due))
	stasis_paused = !biology_due
	return stasis_paused

/// Is this mob's current Life() cycle paused by stasis?
/mob/proc/inStasisNow()
	return FALSE

/mob/living/inStasisNow()
	return body ? body.stasis_paused : FALSE

// --- Sources ---------------------------------------------------------------------

/// A stasis field. Subtypes set the depth through BF_STASIS. Several sources
/// may hold one mob at once (a bag inside a sleeper); the deepest wins.
/datum/modifier/stasis
	name = "stasis"
	desc = "Your bodily functions are slowed to a crawl."
	hidden = TRUE
	stacks = MODIFIER_STACK_ALLOWED
	factors = alist(BF_STASIS = 0.5)
	/// Weakref to what holds the mob in stasis (bag, pod, NIF), or null.
	var/datum/weakref/stasis_source

/datum/modifier/stasis/Destroy(force)
	var/datum/source = stasis_source?.resolve()
	if(source && !QDELETED(source))
		UnregisterSignal(source, COMSIG_QDELETING)
	if(holder && !QDELETED(holder))
		om_clock_set(holder, /datum/object_model/clock_domain/biology, src)
	stasis_source = null
	return ..()

/datum/modifier/stasis/proc/on_stasis_source_deleted(datum/source)
	SIGNAL_HANDLER
	if(holder && !QDELETED(holder))
		holder.remove_specific_modifier(src, TRUE)

/datum/modifier/stasis/on_applied()
	. = ..()
	if(!holder || QDELETED(holder))
		return
	var/datum/body/B = holder.body
	if(B && isnull(B.stasis_last_virtual))
		B.stasis_last_virtual = om_clock_time(holder, /datum/object_model/clock_domain/biology)
	om_clock_set(holder, /datum/object_model/clock_domain/biology, src, 1, factors[BF_STASIS])

/datum/modifier/stasis/on_expire()
	. = ..()
	if(holder && !QDELETED(holder))
		om_clock_set(holder, /datum/object_model/clock_domain/biology, src)

/// Life at half speed.
/datum/modifier/stasis/light
	name = "light stasis"
	factors = alist(BF_STASIS = 0.5)

/// Life at a fifth of normal speed.
/datum/modifier/stasis/moderate
	name = "moderate stasis"
	factors = alist(BF_STASIS = 0.8)

/// Life at a tenth of normal speed (stasis bags).
/datum/modifier/stasis/deep
	name = "deep stasis"
	factors = alist(BF_STASIS = 0.9)

/// Life at a hundredth of normal speed.
/datum/modifier/stasis/complete
	name = "complete stasis"
	factors = alist(BF_STASIS = 0.99)

/// Life stopped outright (cryopods, stasis cages, admin).
/datum/modifier/stasis/total
	name = "total stasis"
	factors = alist(BF_STASIS = 1)

/// Put this mob in stasis `stasis_type` (a /datum/modifier/stasis path) held by
/// `source`, replacing whatever stasis that source applied before. A null type
/// releases the source's stasis. Other sources are untouched. Returns TRUE if
/// anything changed.
/mob/living/proc/set_stasis(stasis_type, datum/source)
	if(stasis_type && !ispath(stasis_type, /datum/modifier/stasis))
		stack_trace("set_stasis() given [stasis_type], not a /datum/modifier/stasis")
		return FALSE
	var/datum/modifier/stasis/current = stasis_modifier_from(source)
	if(current?.type == stasis_type)
		return FALSE
	if(current)
		remove_specific_modifier(current, TRUE)
	var/datum/modifier/stasis/added
	if(stasis_type)
		added = add_modifier(stasis_type, suppress_failure = TRUE)
		if(added)
			added.stasis_source = source ? WEAKREF(source) : null
			if(source)
				added.RegisterSignal(source, COMSIG_QDELETING, TYPE_PROC_REF(/datum/modifier/stasis, on_stasis_source_deleted))
	log_game("STASIS: [key_name(src)] [current ? "left [current.name]" : ""][current && added ? " and " : ""][added ? "entered [added.name]" : ""] from [source ? "[source] ([source.type])" : "no source"] at [AREACOORD(src)]; BF_STASIS now [factor(BF_STASIS)].")
	return TRUE

/// The stasis modifier `source` applied to this mob, or null. A null source
/// matches stasis applied without one (admin).
/mob/living/proc/stasis_modifier_from(datum/source)
	for(var/datum/modifier/stasis/S in modifiers)
		var/datum/held_by = S.stasis_source?.resolve()
		if(held_by == source)
			return S
	return null

/mob/living/proc/has_stasis_from(datum/source)
	return stasis_modifier_from(source) ? TRUE : FALSE
