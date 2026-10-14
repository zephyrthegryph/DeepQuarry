// Clocks: an entity's clock domain runs at a rate (the biological clock at the clock_rate_bio stat), its local time is world time scaled by it, and a
// change of rate folds the time passed in at the old rate, moves the clocked deadlines and re-syncs the cadence rosters. Timers, deadlines and the
// scheduler read the rate and local time here. (doc/rewrite/final_api.html section 3.)

/// The time `E`'s scheduler runs on (world.time live, injected in tests).
/proc/scheduler_time_of(datum/E)
	var/datum/scheduler_record/rec = E?.om_rec
	return rec ? rec.sched.now() : time_scheduler().now()

// ---------------------------------------------------------------- clocks

/// Stride 4 entry for clock `cidx`, created on first need.
/proc/clock_entry(datum/scheduler_record/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return i
	var/t = rec.sched.now()
	LAZYADD(rec.clocks, list(cidx, 1, t, t)) // a clock starts unscaled: its first change then always differs from it and resyncs
	return length(rec.clocks) - 3

/proc/clock_compute(datum/scheduler_record/rec, cidx)
	var/datum/clock_definition/C = definition_registry().clocks[cidx]
	if(C.id == CLOCK_BIO)
		// Biological time runs at the clock_rate_bio stat (MIN, base 1): stasis holds it lower (bio_clock_rate_changed()).
		var/rate = rec.owner.biological_clock_rate()
		return isnull(rate) ? 1 : clamp(rate, C.min_rate, C.max_rate)
	return 1 // no other clock has a rate source

/// The entity's rate in clock `cidx` (1 when nothing modifies it).
/proc/clock_rate(datum/scheduler_record/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return K[i + 1]
	return clock_compute(rec, cidx)

/// Local (clock) time in deciseconds.
/proc/clock_local(datum/scheduler_record/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return K[i + 2] + (rec.sched.now() - K[i + 3]) * K[i + 1]
	return rec.sched.now()

/// Folds elapsed time into local time at the current rate. Always before a rate change.
/proc/clock_settle(datum/scheduler_record/rec, cidx)
	var/i = clock_entry(rec, cidx)
	var/list/K = rec.clocks
	var/t = rec.sched.now()
	K[i + 2] += (t - K[i + 3]) * K[i + 1]
	K[i + 3] = t

/// After a clock effect changed: new rate, clocked deadlines re-inserted,
/// roster re-synced (a zero rate sleeps cadence work).
/proc/clock_changed(datum/scheduler_record/rec, cidx)
	var/i = clock_entry(rec, cidx)
	var/list/K = rec.clocks
	var/new_rate = clock_compute(rec, cidx)
	if(K[i + 1] == new_rate)
		return
	K[i + 1] = new_rate
	deadline_clock_reschedule(rec, cidx)
	entity_sync_all(rec)

/// The time on `E`'s clock `clock_id`, in deciseconds (doc/rewrite/final_api.html section 3). Body and medical code that needs
/// "how much biological time has passed" reads CLOCK_BIO here instead of world.time: it runs at the clock_rate_bio stat, so
/// stasis slows or stops it. An entity whose clock never moved off rate 1 reads its scheduler's time.
/proc/clock_now(datum/E, clock_id)
	var/datum/clock_definition/C = definition_registry().clock_by_id[clock_id]
	if(!C)
		CRASH("om: unknown clock [clock_id]")
	var/datum/scheduler_record/rec = E?.om_rec
	return rec ? clock_local(rec, C.idx) : time_scheduler().now()

/// STAT_CLOCK_RATE_BIO of `E` moved: biological time so far is folded in at the old rate, then the bio clock, its deadlines,
/// timers and cadences take the new one.
/proc/bio_clock_rate_changed(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	var/static/bio_idx
	if(!bio_idx)
		var/datum/clock_definition/C = definition_registry().clock_by_id[CLOCK_BIO]
		bio_idx = C.idx
	clock_settle(rec, bio_idx)
	clock_changed(rec, bio_idx)
	timers_rate_changed(rec)

// ---------------------------------------------------------------- relevance and suspension

/// STAT_RELEVANCE of `E` moved to `level`: the OM record's behaviours pick their cadence by it (rec.relevance) and the Rust side mirrors
/// it; SEQ_KEY_RELEVANCE puts E in or out of the sequences sweeping it (seq_publish()).
/proc/relevance_changed(datum/E, level)
	var/datum/scheduler_record/rec = E.om_rec
	if(rec)
		rec.relevance = level
		entity_sync_all(rec)
	entity_native_relevance(E, level)
	engine_key_changed(E, SEQ_KEY_RELEVANCE)

/// STAT_SUSPENDED of `E` flipped: the OM record's cadences and own-clock timers stop or resume with it.
/proc/suspended_changed(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	entity_sync_all(rec)
	timers_rate_changed(rec)

/// Non-biological entities keep the unmodified clock; the lifeform adapter supplies its stat.
/datum/proc/biological_clock_rate()
	return null
