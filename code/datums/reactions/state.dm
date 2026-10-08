// State and change (code/__defines/reactions.dm).
//
// publish_change(E, key) announces that E's `key` changed. It is demand-gated: TRACKED setters (through
// changed()), timed_set and the ownership accessors call it only when READERS(E, key) says someone reads
// that key, so an unread var costs one assoc lookup. Readers are static (the type's reactions() table,
// which folds in capability reactions, derived() and the generated reads) or dynamic (observe()).
//
// The relation ledger holds the internal relation kinds (GRANT, LISTENER, MEMBER, TIMER, CONTAINED) on the
// same holder-centred footing as the declared REF / PAIRED / OWNED views. Every entry counts its sources:
// the relation is present while any source holds it, so two systems granting the same thing revoke
// independently. Writes publish both ends.

/// Everything a datum holds for the reaction layer, allocated on first use (most datums never have one).
/datum/rx_state
	/// kind -> what -> source -> count (rx_ledger_*).
	var/list/ledger
	/// /datum/rx_listener records observing THIS datum.
	var/list/listeners
	/// /datum/rx_listener records where this datum is the listener.
	var/list/listening
	/// key -> number of dynamic change/cross observers reading it (READERS).
	var/list/observed
	/// notice type -> number of dynamic observers wanting it (WANTS).
	var/list/notice_types
	/// on_cross read -> the last band delivered.
	var/list/bands
	/// urgent on_cross reaction sig -> list(band, previous_band) waiting for its work item's run (work.dm).
	var/list/cross_pending
	/// after(key = ...): key -> list(timer id, token, clock) of the pending keyed timer.
	var/list/timer_ids
	/// Pending operation contexts (/datum/op_ctx) this datum is an end of (actor, target, held, a watched
	/// datum): rx_teardown() cancels them, so a wait never outlives what it is about (operations/op_ctx.dm).
	var/list/pending_ops
	/// Tasks (code/engine/kernel/tasks.dm) that name this datum as actor, target, busy worker or state: its deletion ends them.
	var/list/tasks_on
	/// on_change(at_most =): reaction sig -> when it was last delivered (the scheduler's clock).
	var/list/at_most_last
	/// on_change(at_most =): reaction sig -> the keys held until its window ends.
	var/list/at_most_held

/datum
	/// The reaction layer's per-datum state, or null (see /datum/rx_state).
	var/tmp/datum/rx_state/rx

/// D's reaction state, made when first needed.
/proc/rx_of(datum/D)
	RETURN_TYPE(/datum/rx_state)
	if(!D.rx)
		// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
		D.rx = new
	return D.rx

/// The relation key a ledger kind publishes on its holder (and "<key>_of" on the partner it names).
GLOBAL_LIST_INIT(rx_kind_keys, list(null, null, null, "rel_grant", "rel_listener", "rel_member", "rel_timer", "rel_contained"))

// ---------------------------------------------------------------- READERS

/// TRUE when a static reaction of E's type, a generated / derived() read, or a dynamic observer reads `key`.
/proc/rx_readers(datum/E, key)
	var/datum/rx_table/T = GLOB.rx_tables?[E.type]
	if(isnull(T))
		T = rx_table_build(E)
	if(T && T.read_keys[key])
		return TRUE
	if(E.rx?.observed?[key])
		return TRUE
	if(lifeform_watch_keys?[key] && lifeform_watching(E, key))
		return TRUE // a lifecycle form follows the var: a registry key, a radio frequency, a derives() input (code/engine/lifeforms/forms.dm)
	return hooks_watching(E, key) // an on_change() hook of the engine (code/engine/actions/change.dm)

/// The tracked var `var_name` of E changed (TRACKED setters, a hand-written SETTER): its key is published when
/// someone reads it (READERS) and the outputs that read it re-derive (changed(), refresh.dm). No OM channel is raised:
/// TRACKED_BRIDGED() raises one for a var an OM stage or om_watch() still reads by channel.
/proc/tracked_changed(datum/E, var_name)
	READS_FROM()
	changed(E, 0, var_name)

/// BRIDGE (removed with S4): tracked_changed() for a hand-written setter of a var an OM stage still reads by channel.
/// The channel is the one E's type declares for the var (OM_FIELD_SETTER in machinery_fields.dm: a machine's anchored
/// raises CHANGE_MACHINE_ANCHORED, a mob's CHANGE_MOB_CAN_MOVE, any other atom none), so the setter needs no istype().
/proc/tracked_bridged_changed(datum/E, var_name)
	var/list/fields = om_registry().fields_of(E.type)
	changed(E, fields[var_name] || 0, var_name)

/// A pending operation watching (E, key) counts as a dynamic reader of it while it waits (delta +1 / -1), so
/// publish_change() is called for it and reaches op_reads_changed(). Same table observe() counts in.
/proc/rx_watch_adjust(datum/E, key, delta)
	var/datum/rx_state/S = E.rx
	if(!S)
		if(delta < 0)
			return
		S = rx_of(E)
	if(!S.observed)
		S.observed = list()
	var/n = (S.observed[key] || 0) + delta
	if(n > 0)
		S.observed[key] = n
	else
		S.observed -= key
	if(!length(S.observed))
		S.observed = null

/**
 * `key` of `E` changed. Delivers to the type's on_change / on_cross reactions and to observe()rs of the key
 * (coalesced: a handler runs once per drain however many of its reads changed; see rx_drain()).
 */
/proc/publish_change(datum/E, key)
	if(!E || QDELING(E) || !islist(GLOB?.rx_tables))
		return
	var/datum/rx_table/T = GLOB.rx_tables[E.type]
	if(isnull(T))
		T = rx_table_build(E)
	if(T)
		var/list/hits = T.by_key[key]
		for(var/datum/reaction/R as anything in hits)
			if(R.when && !rx_when_holds(E, R))
				continue // its gate excludes this holder now: nothing is queued
			rx_pend(E, R, key)
		var/list/crossing = T.crosses[key]
		for(var/datum/reaction/R as anything in crossing)
			rx_cross_check(E, R)
	var/datum/rx_state/S = E.rx
	if(S?.listeners)
		for(var/datum/rx_listener/L as anything in S.listeners.Copy())
			var/datum/reaction/R = L.trigger
			if(R.kind == RXN_CHANGE && (key in R.reads))
				rx_pend(E, L, key)
			else if(R.kind == RXN_CROSS && R.key == key)
				rx_cross_check(E, R, L)
	// The on_change() hooks of the engine that read the key are marked for the next drain point.
	if(islist(GLOB?.change_index_by_type) && (GLOB.change_index_by_type[E.type] || E.rx?.hooks || GLOB.change_hop_keys[key]))
		hooks_change_published(E, key)
	// A lifecycle form that follows the var reacts now: a re-key, a retune, a recompute, a scope check (code/engine/lifeforms/forms.dm).
	if(lifeform_watch_keys?[key])
		lifeform_published(E, key)
	// A pending operation watching this read re-checks now (a cheap no-op while nothing is pending).
	if(length(GLOB.op_watchers))
		op_reads_changed(E, key)
	// Sequence steps that read the key wake (code/controllers/kernel/sequence.dm).
	if(E.seq_states)
		seq_publish(E, key)

/// An on_change(when =) gate: a var name truthy on `E`, or a PROC_REF on it answering TRUE.
/proc/rx_when_holds(datum/E, datum/reaction/R)
	if(R.when_var)
		return !!E.vars[R.when]
	return !!call(E, R.when)()

// ---------------------------------------------------------------- the relation ledger

/// Adds `source` as a holder of `what` under `kind` on `holder`, n times. Returns TRUE when `what` was not
/// present before (its first source). Publishes both ends.
/proc/rx_ledger_add(datum/holder, kind, what, source, n = 1)
	if(isnum(what))
		what = "[what]" // a number would index the list, not key it
	if(isnum(source))
		source = "[source]"
	var/datum/rx_state/S = rx_of(holder)
	if(!S.ledger)
		S.ledger = list()
	var/list/whats = S.ledger["[kind]"]
	if(!whats)
		whats = list()
		S.ledger["[kind]"] = whats
	var/list/sources = whats[what]
	. = FALSE
	if(!sources)
		sources = list()
		whats[what] = sources
		. = TRUE
	sources[source] = (sources[source] || 0) + n
	if(.)
		rx_ledger_publish(holder, kind, what)

/// Removes n counts of `source` from `what`. Returns TRUE when `what` has no source left (it is gone).
/proc/rx_ledger_remove(datum/holder, kind, what, source, n = 1)
	if(isnum(what))
		what = "[what]"
	if(isnum(source))
		source = "[source]"
	var/list/whats = holder.rx?.ledger?["[kind]"]
	var/list/sources = whats?[what]
	if(!sources || !sources[source])
		return FALSE
	var/left = sources[source] - n
	if(left > 0)
		sources[source] = left
		return FALSE
	sources -= source
	if(length(sources))
		return FALSE
	whats -= what
	if(!length(whats))
		holder.rx.ledger -= "[kind]"
	rx_ledger_publish(holder, kind, what)
	return TRUE

/// Drops every hold `source` has under `kind` on `holder`. Returns the number of whats that vanished.
/proc/rx_ledger_clear_source(datum/holder, kind, source)
	if(isnum(source))
		source = "[source]"
	var/list/whats = holder.rx?.ledger?["[kind]"]
	. = 0
	for(var/what in whats?.Copy())
		var/list/sources = whats[what]
		if(!sources?[source])
			continue
		if(rx_ledger_remove(holder, kind, what, source, sources[source]))
			.++

/// TRUE while any source holds `what` under `kind` on `holder`.
/proc/rx_ledger_has(datum/holder, kind, what)
	if(isnum(what))
		what = "[what]"
	return !!holder.rx?.ledger?["[kind]"]?[what]

/// How many counts across every source hold `what`.
/proc/rx_ledger_count(datum/holder, kind, what)
	if(isnum(what))
		what = "[what]"
	. = 0
	var/list/sources = holder.rx?.ledger?["[kind]"]?[what]
	for(var/source in sources)
		. += sources[source]

/// The sources holding `what` (a fresh list).
/proc/rx_ledger_sources(datum/holder, kind, what)
	if(isnum(what))
		what = "[what]"
	var/list/sources = holder.rx?.ledger?["[kind]"]?[what]
	return sources ? sources.Copy() : list()

/// Every `what` present under `kind` (a fresh list of keys).
/proc/rx_ledger_whats(datum/holder, kind)
	var/list/whats = holder.rx?.ledger?["[kind]"]
	var/list/out = list()
	for(var/what in whats)
		out += what
	return out

/// A relation write publishes the holder's key, and the partner's when `what` is a datum.
/proc/rx_ledger_publish(datum/holder, kind, what)
	var/key = GLOB.rx_kind_keys[kind]
	if(!key)
		return
	if(READERS(holder, key))
		publish_change(holder, key)
	if(isdatum(what))
		var/datum/partner = what
		if(!QDELING(partner))
			var/partner_key = "[key]_of"
			if(READERS(partner, partner_key))
				publish_change(partner, partner_key)

// ---------------------------------------------------------------- grants

/**
 * `source` grants `what` (a bit name, a permission) to `target`, for `duration`
 * deciseconds of target's clock when given, else until revoke(). The grant is present while any source
 * holds it. Returns TRUE when it was not present before.
 */
/proc/legacy_grant(datum/target, what, source = "grant", duration)
	if(!target || (isdatum(target) && QDELING(target)))
		return FALSE
	. = rx_ledger_add(target, RELK_GRANT, what, source)
	if(duration)
		after(target, duration, GLOBAL_PROC_REF(rx_grant_expire), key = "grant:[what]:[source]", with = list(target, what, source), keeps_dead = TRUE)

/// Withdraws `source`'s hold on `what`. Returns TRUE when the grant is gone (no source left).
/proc/legacy_revoke(datum/target, what, source = "grant")
	if(!target)
		return FALSE
	return rx_ledger_remove(target, RELK_GRANT, what, source)

/proc/rx_grant_expire(datum/target, what, source)
	if(target && !QDELETED(target))
		legacy_revoke(target, what, source)

/// TRUE while `what` is granted to `target` by any source.
/proc/legacy_granted(datum/target, what)
	return rx_ledger_has(target, RELK_GRANT, what)

// ---------------------------------------------------------------- membership

// MEMBER relations live in the kernel's one membership store (controllers/kernel/membership.dm). A key is what
// members belong to: a /datum/system's type (its singleton is the owner), a capability type, or any datum used as
// a system. join() / leave() are the relation API: they add the source, publish both ends (rel_member on the
// system, rel_member_of on the member) and run the system's on_join() / on_leave() hook.

/// The membership key of `system`: a /datum/system stands for its type, anything else for itself.
/proc/member_key(system)
	if(istype(system, /datum/system))
		var/datum/system/S = system
		return S.type
	return system

/// `E` joins `system` (a /datum/system, its type, a capability type, or any datum used as a system), held by
/// `source` (a capability key, a datum, text), optionally under `role` (indexed for members_of(system, role)).
/// Returns TRUE on first membership.
/proc/join(system, datum/E, source = "join", role = null)
	if(!system || !E || QDELING(E))
		return FALSE
	var/datum/owner = rx_member_owner(system)
	if(owner && QDELING(owner))
		return FALSE
	if(!isnull(role) && istype(owner, /datum/system))
		var/datum/system/declared = owner
		if(length(declared.roles) && !(role in declared.roles))
			CRASH("join: [role] is not a role of [declared.type] (it declares [jointext(declared.roles, ", ")])")
	. = member_join(system, E, source, role)
	if(!.)
		return
	if(owner)
		rx_ledger_publish(owner, RELK_MEMBER, E)
	if(istype(owner, /datum/system))
		var/datum/system/S = owner
		S.on_join(E)

/// `source` withdraws E from system (`all`: every source). Returns TRUE when E is no longer a member.
/proc/leave(system, datum/E, source = "join", all = FALSE)
	if(!system || !E)
		return FALSE
	. = member_leave(system, E, source, all)
	if(!.)
		return
	var/datum/owner = rx_member_owner(system)
	if(owner)
		rx_ledger_publish(owner, RELK_MEMBER, E)
	if(istype(owner, /datum/system))
		var/datum/system/S = owner
		S.on_leave(E)

/// The datum a membership key stands for, when there is one: the system itself, the registered singleton of a
/// /datum/system type, or the datum used as a system. A capability type has none.
/proc/rx_member_owner(system)
	RETURN_TYPE(/datum)
	if(isdatum(system))
		return system
	if(ispath(system, /datum/system))
		return system_table()[system]
	return null

/// TRUE when `E` is a member of `system` through any source.
/proc/is_member(system, datum/E)
	return member_is(system, E)

// ---------------------------------------------------------------- teardown

/// Phase 4 of a datum's destruction (own_teardown): every listener record it is an end of goes, it leaves
/// every system it joined, and its ledger is dropped. Both ends are cleaned, so nothing keeps it alive.
/proc/rx_teardown(datum/D)
	var/datum/type_table/engine_table = type_table_cache()[D.type]
	if(engine_table?.hook_flags & ENGINE_HOOK_DESTROY)
		engine_holder_destroy(D)
	if(D.rx?.activations || D.rx?.sourced)
		activations_teardown(D)
	if(D.rx?.stats)
		stat_sources_teardown(D)
	if(D.seq_states)
		seq_teardown(D) // its sequence states go first: they leave their sweeps themselves
	member_teardown(D) // a member with no reaction state still leaves what it joined
	var/datum/rx_state/S = D.rx
	if(!S)
		return
	// Operations waiting on this datum (as actor, target, held, provider or watched read) are cancelled first.
	for(var/datum/op_ctx/ctx as anything in S.pending_ops?.Copy())
		op_cancel(ctx, /datum/msg/req_cancelled)
	for(var/datum/task/T as anything in S.tasks_on?.Copy())
		T.datum_gone(D)
	for(var/datum/rx_listener/L as anything in S.listeners?.Copy())
		rx_listener_remove(L)
	for(var/datum/rx_listener/L as anything in S.listening?.Copy())
		rx_listener_remove(L)
	GLOB.rx_pending -= D
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	D.rx = null
