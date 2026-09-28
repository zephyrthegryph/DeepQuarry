// Object-model core: cross-entity event hooks (object_model_core.md sec 10).
//
// A behaviour handles events emitted on its own entity. A hook lets any datum
// react to an event emitted on ANOTHER entity: om_hook(source, /datum/om/event/x,
// listener, PROC_REF(on_x)) calls listener.on_x(source, event) whenever x is
// emitted on source, after source's own behaviours, in hook order. A numeric
// return is ORed into event.result; on a before/ event EVENT_VETO refuses it.
//
// Both ends hold the hook: it goes away with om_unhook(), or when either end is
// deleted (lifecycle phase 4, om_teardown_hooks()), so a hook never keeps a
// deleted datum alive and a listener never needs a deleting hook just to clean up.
// Hooks honour event ancestry, as behaviours do: a hook on /datum/om/event/x also
// hears every subtype of x (om_deliver() walks reg.event_lineage).

/// Hooks `listener`'s `proc_ref` to `event_path` (a type or a list of types) emitted
/// on `source`. Re-hooking the same listener and event replaces the proc.
/proc/om_hook(datum/source, event_path, datum/listener, proc_ref)
	if(islist(event_path))
		for(var/path in event_path)
			om_hook(source, path, listener, proc_ref)
		return TRUE
	var/datum/om/rec/srec = source && om_rec_of(source)
	var/datum/om/rec/lrec = listener && om_rec_of(listener)
	if(!srec || !lrec)
		return FALSE
	LAZYINITLIST(srec.hooks_in)
	var/list/hooks = srec.hooks_in[event_path]
	if(!hooks)
		hooks = list()
		srec.hooks_in[event_path] = hooks
	for(var/i in 1 to length(hooks) step 2)
		if(hooks[i] == listener)
			hooks[i + 1] = proc_ref
			return TRUE
	hooks += list(listener, proc_ref)
	LAZYADD(lrec.hooks_out, source)
	return TRUE

/// Removes `listener`'s hooks on `source` for `event_path` (a type, a list of
/// types, or null for every event).
/proc/om_unhook(datum/source, event_path, datum/listener)
	var/datum/om/rec/srec = source?.om_rec
	if(!srec?.hooks_in || !listener)
		return
	var/list/paths
	if(isnull(event_path))
		paths = srec.hooks_in.Copy()
	else if(islist(event_path))
		paths = event_path
	else
		paths = list(event_path)
	var/datum/om/rec/lrec = listener.om_rec
	for(var/path in paths)
		var/list/hooks = srec.hooks_in[path]
		if(!hooks)
			continue
		for(var/i in 1 to length(hooks) step 2)
			if(hooks[i] != listener)
				continue
			hooks.Cut(i, i + 2)
			if(lrec?.hooks_out)
				lrec.hooks_out -= source
			break
		if(!length(hooks))
			srec.hooks_in -= path
	if(!length(srec.hooks_in))
		srec.hooks_in = null
	if(lrec && !length(lrec.hooks_out))
		lrec.hooks_out = null

/// Removes every hook `listener` has on anything.
/proc/om_unhook_all(datum/listener)
	var/datum/om/rec/lrec = listener?.om_rec
	if(!lrec?.hooks_out)
		return
	for(var/datum/source as anything in lrec.hooks_out.Copy())
		om_unhook(source, null, listener)
	lrec.hooks_out = null

/// TRUE when `listener` has a hook on `source` for `event_path`.
/proc/om_hooked(datum/source, event_path, datum/listener)
	var/list/hooks = source?.om_rec?.hooks_in?[event_path]
	if(!hooks)
		return FALSE
	for(var/i in 1 to length(hooks) step 2)
		if(hooks[i] == listener)
			return TRUE
	return FALSE

/// Lifecycle phase 4: drops every hook this entity has, both ways.
/proc/om_teardown_hooks(datum/om/rec/rec)
	var/datum/E = rec.owner
	if(rec.hooks_out)
		var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
		for(var/datum/source as anything in rec.hooks_out.Copy())
			// A doomed source drops its whole hooks_in in its own teardown (below): no
			// per-hook bookkeeping on it (doc/rewrite/init_and_turfs.md sec 4.4 step 3).
			if(batch && batch.doomed[source] && source.gc_destroyed == GC_BATCH_DOOMED)
				continue
			om_unhook(source, null, E)
		rec.hooks_out = null
	if(rec.hooks_in)
		for(var/path in rec.hooks_in)
			var/list/hooks = rec.hooks_in[path]
			for(var/i in 1 to length(hooks) step 2)
				var/datum/listener = hooks[i]
				var/datum/om/rec/lrec = listener.om_rec
				if(lrec?.hooks_out)
					lrec.hooks_out -= E
					if(!length(lrec.hooks_out))
						lrec.hooks_out = null
		rec.hooks_in = null

// ---------------------------------------------------------------- the world

/// The entity world-wide events are emitted on (was the DCS global signal target,
/// SEND_GLOBAL_SIGNAL). Hook it with om_hook(OM_WORLD, /datum/om/event/x, ...).
/datum/om_world
GLOBAL_DATUM_INIT(om_world, /datum/om_world, new)
