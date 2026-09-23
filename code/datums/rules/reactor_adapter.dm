// The one coupling point between rules and the reactor (doc/rewrite/reactor.md §1).
//
// Rules call only the dq_rx_* procs below, and receive wakes as
// rule_wake(reason, source) on the subscriber. Nothing else in
// code/datums/rules/ knows how subscriptions are stored or delivered.
//
//   dq_rx_when_threshold(D, handle, ch, above, level, edges)  REACT_WHEN(D, COND_ABOVE/BELOW[_EDGES])
//   dq_rx_when_band(D, handle, ch, levels)                     REACT_WHEN(D, COND_BAND)
//   dq_rx_on_change(D, handle, ch)                             REACT_ON(D, handle, CH_BIT(ch))
//   dq_rx_on_key(D, kind, id, mask) / dq_rx_publish(...)       REACT_ON_KEY / REACT_PUBLISH
//   dq_rx_at(D, time)                                          REACT_AT
//   dq_rx_rate_linear/read/set_rate/remove, dq_rx_on_rate      RATE_LINEAR ... / REACT_RATE
//   dq_rx_cancel(D, token), dq_rx_clear(D)                     REACT_CANCEL / REACT_CLEAR
//   dq_rx_id(D)                                                REACT_ID
//   dq_rx_node_new/write/read/free                             DM-written channel cells
//
// ============================================================================
// P4-LOCAL STUB. SSreactor (S1, branch rewrite/s1) had not merged when P4 was
// built, so every proc here runs on /datum/dq_rx_stub, a minimal DM model of
// the reactor.md API: condition watches on DM-written channel cells, DM-owned
// keys, one-shot timers and linear rate models, with wakes merged per
// subscriber and delivered on the next flush. It is NOT a scheduler for
// anything but rules. After S1 merges, replace each proc body with the REACT_*
// macro named beside it, map rule_wake() to /datum/proc/on_react(), and map
// the node procs to the probe domain (react_probe_set) until item heat nodes
// exist in the heat domain. Then delete /datum/dq_rx_stub.
// ============================================================================

// DQ_RX_REASON_* and DQ_RX_CH_* live in code/__defines/rules.dm.

/// Called with the merged reasons of a wake. Read the current state; never count wakes.
/datum/proc/rule_wake(reason, source)
	return

/proc/dq_rx()
	var/static/datum/dq_rx_stub/stub
	if(!stub)
		stub = new
	return stub

/proc/dq_rx_id(datum/D)
	return dq_rx().id_of(D)

/proc/dq_rx_now()
	return dq_rx().now()

/proc/dq_rx_when_threshold(datum/D, handle, ch, above, level, edges)
	return dq_rx().add_watch(D, RULE_TRIGGER_THRESHOLD, handle, ch, list(above, level, edges))

/proc/dq_rx_when_band(datum/D, handle, ch, list/levels)
	return dq_rx().add_watch(D, RULE_TRIGGER_BAND, handle, ch, levels.Copy())

/proc/dq_rx_on_change(datum/D, handle, ch)
	return dq_rx().add_watch(D, RULE_TRIGGER_DIFFERENCE, handle, ch, null)

/proc/dq_rx_on_key(datum/D, kind, id, mask)
	return dq_rx().add_key(D, kind, id, mask)

/proc/dq_rx_publish(kind, id, mask)
	dq_rx().publish(kind, id, mask)

/proc/dq_rx_at(datum/D, time)
	return dq_rx().add_timer(D, time, DQ_RX_REASON_TIMER, null)

/proc/dq_rx_cancel(datum/D, token)
	dq_rx().cancel(token)

/proc/dq_rx_clear(datum/D)
	dq_rx().clear(D)

/proc/dq_rx_rate_linear(v0, per_second, lo, hi)
	return dq_rx().rate_new(v0, per_second, lo, hi)

/proc/dq_rx_rate_read(model)
	return dq_rx().rate_read(model)

/proc/dq_rx_rate_set_rate(model, per_second)
	dq_rx().rate_set_rate(model, per_second)

/proc/dq_rx_rate_remove(model)
	dq_rx().rate_remove(model)

/// Wake D when `model` reaches `level` (above) or falls to it (!above); at once if it already has.
/proc/dq_rx_on_rate(datum/D, model, above, level)
	return dq_rx().add_rate_watch(D, model, above, level)

/proc/dq_rx_node_new(list/initial)
	return dq_rx().node_new(initial)

/proc/dq_rx_node_write(handle, ch, value)
	dq_rx().node_write(handle, ch, value)

/proc/dq_rx_node_read(handle, ch)
	return dq_rx().node_read(handle, ch)

/proc/dq_rx_node_free(handle)
	dq_rx().node_free(handle)

/// Deliver pending wakes now. Tests call it; live, it runs on the next tick.
/proc/dq_rx_flush()
	dq_rx().flush()

/// Tests: move the reactor clock forward by `ds` deciseconds, fire due timers, flush.
/proc/dq_rx_test_advance(ds)
	var/datum/dq_rx_stub/stub = dq_rx()
	stub.clock_offset += ds
	stub.run_due()
	stub.flush()

// ---- The stub (see the banner above) ----

/datum/dq_rx_stub
	var/next_token = 1
	var/next_handle = 1
	var/next_id = 1
	/// Tests move the clock without waiting.
	var/clock_offset = 0
	/// datum -> id.
	var/list/ids = list()
	/// "[handle]" -> list(ch -> value).
	var/list/nodes = list()
	/// "[token]" -> list(subscriber, kind, handle, ch, params, last) for watches;
	/// list(subscriber, "key", key) for keys; list(subscriber, "timer", time, reason, source) for timers.
	var/list/subs = list()
	/// "[handle]" -> tokens watching it.
	var/list/by_handle = list()
	/// "[kind]:[id]" -> tokens.
	var/list/by_key = list()
	/// datum -> tokens.
	var/list/by_sub = list()
	/// Timer tokens not yet fired.
	var/list/timers = list()
	/// "[model]" -> list(v0, per_second, t0, lo, hi).
	var/list/rates = list()
	/// "[model]" -> rate watch tokens; each rate watch owns a timer token.
	var/list/rate_watches = list()
	var/next_model = 1
	/// subscriber -> list(reason, source), delivered on flush.
	var/list/pending = list()
	var/flush_queued = FALSE

/datum/dq_rx_stub/proc/now()
	return world.time + clock_offset

/datum/dq_rx_stub/proc/id_of(datum/D)
	. = ids[D]
	if(!.)
		. = next_id++
		ids[D] = .

/datum/dq_rx_stub/proc/track(datum/D, token, list/entry)
	subs["[token]"] = entry
	LAZYADD(by_sub[D], token)

/datum/dq_rx_stub/proc/wake(datum/D, reason, source)
	var/list/entry = pending[D]
	if(entry)
		entry[1] |= reason
	else
		pending[D] = list(reason, source)
	if(!flush_queued)
		flush_queued = TRUE
		addtimer(CALLBACK(src, PROC_REF(flush)), 1)

/datum/dq_rx_stub/proc/flush()
	flush_queued = FALSE
	while(length(pending))
		var/list/batch = pending
		pending = list()
		for(var/datum/D as anything in batch)
			if(QDELETED(D))
				continue
			var/list/entry = batch[D]
			D.rule_wake(entry[1], entry[2])

// Watches

/datum/dq_rx_stub/proc/add_watch(datum/D, kind, handle, ch, params)
	var/token = next_token++
	var/list/entry = list(D, kind, handle, ch, params, null)
	entry[6] = watch_state(entry)
	track(D, token, entry)
	LAZYADD(by_handle["[handle]"], token)
	return token

/// The watch's current state: TRUE/FALSE for thresholds, the band index for bands.
/datum/dq_rx_stub/proc/watch_state(list/entry)
	var/value = node_read(entry[3], entry[4])
	var/list/params = entry[5]
	switch(entry[2])
		if(RULE_TRIGGER_THRESHOLD)
			if(isnull(value))
				return FALSE
			return params[1] ? value >= params[2] : value <= params[2]
		if(RULE_TRIGGER_BAND)
			if(isnull(value))
				return 0
			. = 0
			for(var/level in params)
				if(value >= level)
					.++
		else
			return value

/datum/dq_rx_stub/proc/node_new(list/initial)
	var/handle = next_handle++
	nodes["[handle]"] = initial ? initial.Copy() : list()
	return handle

/datum/dq_rx_stub/proc/node_read(handle, ch)
	var/list/node = nodes["[handle]"]
	return node ? node["[ch]"] : null

/datum/dq_rx_stub/proc/node_write(handle, ch, value)
	var/list/node = nodes["[handle]"]
	if(!node || node["[ch]"] == value)
		return
	node["[ch]"] = value
	for(var/token in by_handle["[handle]"])
		var/list/entry = subs["[token]"]
		if(!entry || entry[4] != ch)
			continue
		var/state = watch_state(entry)
		if(state == entry[6])
			continue
		var/old = entry[6]
		entry[6] = state
		switch(entry[2])
			if(RULE_TRIGGER_THRESHOLD)
				var/list/params = entry[5]
				if(state || params[3])
					wake(entry[1], DQ_RX_REASON_CONDITION, handle)
			if(RULE_TRIGGER_BAND)
				wake(entry[1], DQ_RX_REASON_CONDITION, handle)
			else
				if(old != state)
					wake(entry[1], DQ_RX_REASON_CHANGED, handle)

/datum/dq_rx_stub/proc/node_free(handle)
	nodes -= "[handle]"
	by_handle -= "[handle]"

// Keys

/datum/dq_rx_stub/proc/add_key(datum/D, kind, id, mask)
	var/token = next_token++
	var/key = "[kind]:[id]"
	track(D, token, list(D, "key", key, mask))
	LAZYADD(by_key[key], token)
	return token

/datum/dq_rx_stub/proc/publish(kind, id, mask)
	var/key = "[kind]:[id]"
	for(var/token in by_key[key])
		var/list/entry = subs["[token]"]
		if(entry && (entry[4] & mask))
			wake(entry[1], DQ_RX_REASON_KEY, id)

// Timers

/datum/dq_rx_stub/proc/add_timer(datum/D, time, reason, source)
	var/token = next_token++
	track(D, token, list(D, "timer", time, reason, isnull(source) ? token : source))
	timers += token
	var/delay = time - now()
	if(delay <= 0)
		run_due()
	else
		addtimer(CALLBACK(src, PROC_REF(run_due)), delay)
	return token

/datum/dq_rx_stub/proc/run_due()
	var/time = now()
	for(var/token in timers.Copy())
		var/list/entry = subs["[token]"]
		if(!entry)
			timers -= token
			continue
		if(entry[3] > time)
			continue
		timers -= token
		forget(token)
		wake(entry[1], entry[4], entry[5])

// Rate models

/datum/dq_rx_stub/proc/rate_new(v0, per_second, lo, hi)
	var/model = next_model++
	rates["[model]"] = list(v0, per_second, now(), lo, hi)
	return model

/datum/dq_rx_stub/proc/rate_read(model)
	var/list/rate = rates["[model]"]
	if(!rate)
		return null
	. = rate[1] + rate[2] * (now() - rate[3]) / 10
	if(!isnull(rate[4]))
		. = max(., rate[4])
	if(!isnull(rate[5]))
		. = min(., rate[5])

/datum/dq_rx_stub/proc/rate_set_rate(model, per_second)
	var/list/rate = rates["[model]"]
	if(!rate)
		return
	rate[1] = rate_read(model)
	rate[2] = per_second
	rate[3] = now()
	for(var/token in rate_watches["[model]"])
		schedule_rate_watch(token)

/datum/dq_rx_stub/proc/rate_remove(model)
	for(var/token in rate_watches["[model]"])
		cancel(token)
	rates -= "[model]"
	rate_watches -= "[model]"

/datum/dq_rx_stub/proc/add_rate_watch(datum/D, model, above, level)
	var/token = next_token++
	track(D, token, list(D, "rate", model, above, level, null))
	LAZYADD(rate_watches["[model]"], token)
	schedule_rate_watch(token)
	return token

/// (Re)arm a rate watch's timer for the exact crossing time.
/datum/dq_rx_stub/proc/schedule_rate_watch(token)
	var/list/entry = subs["[token]"]
	if(!entry)
		return
	if(entry[6])
		cancel(entry[6])
		entry[6] = null
	var/list/rate = rates["[entry[3]]"]
	if(!rate)
		return
	var/value = rate_read(entry[3])
	var/above = entry[4]
	var/level = entry[5]
	if(above ? value >= level : value <= level)
		wake(entry[1], DQ_RX_REASON_RATE, entry[3])
		return
	var/per_second = rate[2]
	if(!per_second || (above && per_second < 0) || (!above && per_second > 0))
		return
	var/ds = CEILING((level - value) / per_second * 10, 1)
	entry[6] = add_timer(entry[1], now() + ds, DQ_RX_REASON_RATE, entry[3])

// Cancelling

/datum/dq_rx_stub/proc/forget(token)
	var/list/entry = subs["[token]"]
	if(!entry)
		return
	subs -= "[token]"
	var/datum/D = entry[1]
	LAZYREMOVE(by_sub[D], token)
	return entry

/datum/dq_rx_stub/proc/cancel(token)
	var/list/entry = forget(token)
	if(!entry)
		return
	switch(entry[2])
		if("key")
			LAZYREMOVE(by_key[entry[3]], token)
		if("timer")
			timers -= token
		if("rate")
			LAZYREMOVE(rate_watches["[entry[3]]"], token)
			if(entry[6])
				cancel(entry[6])
		else
			LAZYREMOVE(by_handle["[entry[3]]"], token)

/datum/dq_rx_stub/proc/clear(datum/D)
	var/list/tokens = by_sub[D]
	if(tokens)
		for(var/token in tokens.Copy())
			cancel(token)
	by_sub -= D
	pending -= D
	ids -= D
