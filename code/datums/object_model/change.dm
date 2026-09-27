// Sparse, typed change tracking and behaviour-owned derived views. A group is
// one bit in the subject type's change schema. No state is allocated until a
// view or revision reader asks for it.
#define OM_CHANGE_MAX_MASK 16777215
#define OM_READ_INCOMING 1
#define OM_READ_OUTGOING 2
#define OM_DERIVED_VALUE 1
#define OM_DERIVED_READY 2
#define OM_DERIVED_DIRTY 3
#define OM_DERIVED_OBSERVERS 4
#define OM_DERIVED_COMPUTING 5

/datum/object_model/change_state
	var/datum/subject
	var/list/views
	var/list/tracked_revisions
	var/tracked_mask = 0
	var/generation = 0
	var/pending = FALSE

/datum/object_model/change_state/Destroy()
	subject = null
	views = null
	tracked_revisions = null
	return ..()

/proc/om_change_state_for(datum/subject, create = FALSE)
	if(!subject || QDELETED(subject))
		return null
	var/datum/object_model/state/model = create ? om_state_for(subject) : subject.om_state
	if(!model)
		return null
	if(!model.change && create)
		model.change = new /datum/object_model/change_state
		model.change.subject = subject
	return model.change

/proc/om_change_mask_valid(mask)
	return isnum(mask) && mask > 0 && mask <= OM_CHANGE_MAX_MASK && mask == round(mask)

/proc/om_change_bit_index(group)
	var/bit = 1
	for(var/index in 1 to 24)
		if(bit == group)
			return index
		bit *= 2
	return 0

/// Request a revision only for groups that actually need one. One group bit
/// per call keeps the returned stamp cheap and unambiguous.
/proc/om_track_change(datum/subject, group)
	if(!om_change_mask_valid(group) || (group & (group - 1)))
		CRASH("object-model revision group must be one bit: [group]")
	var/datum/object_model/archetype/A = om_archetype_for(subject?.type, subject)
	if(!A || !(A.tracked_groups & group))
		CRASH("[subject?.type] does not declare tracked change group [group]")
	var/datum/object_model/change_state/state = om_change_state_for(subject, TRUE)
	if(!state)
		return null
	if(!state.tracked_revisions)
		state.tracked_revisions = new/list(24)
	state.tracked_mask |= group
	var/index = om_change_bit_index(group)
	return state.tracked_revisions[index] || 0

/proc/om_change_revision(datum/subject, group)
	if(!om_change_mask_valid(group) || (group & (group - 1)))
		CRASH("object-model revision group must be one bit: [group]")
	var/datum/object_model/change_state/state = om_change_state_for(subject)
	if(!state || !(state.tracked_mask & group))
		return null
	return state.tracked_revisions[om_change_bit_index(group)] || 0

/// Call after an authoritative write. Legacy cache/watch consumers still get
/// the ordinary om_changed wake; typed views use the compact mask directly.
/proc/om_mark_changed(datum/subject, mask)
	if(!subject || QDELETED(subject))
		return
	if(!om_change_mask_valid(mask))
		CRASH("invalid object-model change mask [mask]")
	var/datum/object_model/archetype/A = om_archetype_for(subject.type, subject)
	if(!A || (mask & ~A.tracked_groups))
		CRASH("[subject.type] publishes undeclared object-model change groups [mask]")
	var/datum/object_model/change_state/state = om_change_state_for(subject)
	if(state)
		state.generation++
		if(state.tracked_mask & mask)
			var/bit = 1
			for(var/index in 1 to 24)
				if(mask & state.tracked_mask & bit)
					state.tracked_revisions[index] = (state.tracked_revisions[index] || 0) + 1
				bit *= 2
		om_derived_invalidate_local(state, mask)
	// A ledger caches a member's property snapshot. Only declared producer
	// groups trigger the expensive refresh; unrelated tracked writes stay cheap.
	if(istype(subject, /atom/movable))
		var/atom/movable/member = subject
		var/datum/ledger/parent_ledger = member.loc?.ledger
		if(parent_ledger?.entries?[member])
			if(A?.ledger_contribution_groups & mask)
				parent_ledger.refresh(member)
	om_derived_propagate(subject, mask)
	om_bump_revision_if_tracked(subject)
	om_changed(subject, null, mask)
	subject.om_state?.behaviour_runtime?.wake_changed(mask)

/// Each derived behaviour declares its local input bits and, optionally,
/// ownership/relation inputs. Return scalars or immutable snapshots. A list
/// result needs a value-based derived_equal() override.
/datum/object_model/behaviour/proc/compute_derived(datum/source, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	CRASH("behaviour [type] has no derived computation")

/datum/object_model/behaviour/proc/derived_equal(old_value, new_value)
	return old_value == new_value

/datum/object_model/behaviour/proc/on_derived_changed(datum/source, old_value, new_value, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return

/proc/om_derived_entry(datum/object_model/change_state/state, behaviour_path)
	if(!state.views)
		state.views = list()
	var/list/entry = state.views[behaviour_path]
	if(!entry)
		entry = list(null, FALSE, TRUE, 0, FALSE)
		state.views[behaviour_path] = entry
	return entry

/// Fresh on every read. Multiple writes before the read require one compute.
/proc/om_derived_read(datum/subject, behaviour_path)
	if(!subject || QDELETED(subject))
		return null
	var/datum/object_model/archetype/A = om_archetype_for(subject.type, subject)
	if(!A || !(behaviour_path in A.behaviours))
		CRASH("[subject.type] does not declare derived behaviour [behaviour_path]")
	var/datum/object_model/behaviour/B = om_behaviour(behaviour_path)
	if(!B)
		CRASH("invalid derived behaviour [behaviour_path]")
	var/datum/object_model/change_state/state = om_change_state_for(subject, TRUE)
	var/list/entry = om_derived_entry(state, behaviour_path)
	if(entry[OM_DERIVED_READY] && !entry[OM_DERIVED_DIRTY])
		return entry[OM_DERIVED_VALUE]
	if(entry[OM_DERIVED_COMPUTING])
		CRASH("recursive derived computation on [subject.type] [behaviour_path]")
	entry[OM_DERIVED_COMPUTING] = TRUE
	var/previous = entry[OM_DERIVED_VALUE]
	var/had_previous = entry[OM_DERIVED_READY]
	var/result
	var/stable = FALSE
	for(var/attempt in 1 to 3)
		var/generation_before = state.generation
		result = B.compute_derived(subject, A.behaviours[behaviour_path])
		if(QDELETED(subject) || subject.om_state?.change != state)
			entry[OM_DERIVED_COMPUTING] = FALSE
			return null
		if(generation_before == state.generation)
			stable = TRUE
			break
	if(!stable)
		entry[OM_DERIVED_COMPUTING] = FALSE
		CRASH("derived value changed repeatedly during computation: [subject.type] [behaviour_path]")
	entry[OM_DERIVED_VALUE] = result
	entry[OM_DERIVED_READY] = TRUE
	entry[OM_DERIVED_DIRTY] = FALSE
	entry[OM_DERIVED_COMPUTING] = FALSE
	if(had_previous && entry[OM_DERIVED_OBSERVERS] && !B.derived_equal(previous, result))
		B.on_derived_changed(subject, previous, result, A.behaviours[behaviour_path])
	return result

/proc/om_derived_dirty(datum/object_model/change_state/state, behaviour_path, list/entry)
	if(entry[OM_DERIVED_DIRTY])
		return
	entry[OM_DERIVED_DIRTY] = TRUE
	state.generation++
	if(entry[OM_DERIVED_OBSERVERS] && !state.pending)
		state.pending = TRUE
		om_wake(state, state, "derived_flush")

/datum/object_model/change_state/om_on_wake(datum/entity, reason)
	if(entity == src && reason == "derived_flush")
		flush()

/datum/object_model/change_state/proc/flush()
	SHOULD_NOT_SLEEP(TRUE)
	pending = FALSE
	if(!subject || QDELETED(subject) || subject.om_state?.change != src || !views)
		return
	for(var/behaviour_path in views.Copy())
		var/list/entry = views[behaviour_path]
		if(entry && entry[OM_DERIVED_DIRTY] && entry[OM_DERIVED_OBSERVERS])
			om_derived_read(subject, behaviour_path)

/proc/om_derived_invalidate_local(datum/object_model/change_state/state, mask)
	if(!state?.views)
		return
	for(var/behaviour_path in state.views)
		var/datum/object_model/behaviour/B = om_behaviour(behaviour_path)
		if(B.derived_input_mask & mask)
			om_derived_dirty(state, behaviour_path, state.views[behaviour_path])

/proc/om_derived_invalidate_owned(datum/owner, slot_id, mask, membership = FALSE)
	om_scheduled_wake_owned(owner, slot_id, mask, membership)
	var/datum/object_model/change_state/state = om_change_state_for(owner)
	if(!state?.views)
		return
	for(var/behaviour_path in state.views)
		var/datum/object_model/behaviour/B = om_behaviour(behaviour_path)
		for(var/list/input as anything in B.derived_owned_inputs)
			if(input[1] == slot_id && (membership || (input[2] & mask)))
				om_derived_dirty(state, behaviour_path, state.views[behaviour_path])
				break

/proc/om_derived_invalidate_relation(datum/subject, relation_path, direction, mask, membership = FALSE)
	om_scheduled_wake_relation(subject, relation_path, direction, mask, membership)
	var/datum/object_model/change_state/state = om_change_state_for(subject)
	if(!state?.views)
		return
	for(var/behaviour_path in state.views)
		var/datum/object_model/behaviour/B = om_behaviour(behaviour_path)
		for(var/list/input as anything in B.derived_relation_inputs)
			if(input[1] == relation_path && input[2] == direction && (membership || (input[3] & mask)))
				om_derived_dirty(state, behaviour_path, state.views[behaviour_path])
				break

/proc/om_derived_propagate(datum/subject, mask)
	var/datum/owner = om_owner(subject)
	if(owner)
		om_derived_invalidate_owned(owner, om_owner_slot(subject), mask)
	// Physical containment is virtual: loc is authoritative and has no stored
	// relation edge to walk here. Only an already observed holder has work.
	if(istype(subject, /atom/movable))
		var/atom/movable/movable_subject = subject
		if(movable_subject.loc?.om_state?.change || movable_subject.loc?.om_state?.behaviour_runtime)
			om_derived_invalidate_relation(movable_subject.loc, /datum/object_model/relation/physical_contents, OM_READ_OUTGOING, mask)
			var/datum/ledger/slot_ledger = movable_subject.loc.ledger
			if(slot_ledger?.entries?[movable_subject])
				om_derived_invalidate_relation(movable_subject.loc, /datum/object_model/relation/slot_member, OM_READ_OUTGOING, mask)
	var/datum/object_model/state/model = subject.om_state
	for(var/relation_path in model?.outgoing)
		for(var/datum/target as anything in model.outgoing[relation_path])
			om_derived_invalidate_relation(target, relation_path, OM_READ_INCOMING, mask)
	for(var/relation_path in model?.incoming)
		for(var/datum/source as anything in model.incoming[relation_path])
			om_derived_invalidate_relation(source, relation_path, OM_READ_OUTGOING, mask)

/proc/om_derived_owned_membership_changed(datum/owner, slot_id)
	om_derived_invalidate_owned(owner, slot_id, 0, TRUE)

/proc/om_derived_relation_membership_changed(datum/source, relation_path, datum/target)
	om_derived_invalidate_relation(source, relation_path, OM_READ_OUTGOING, 0, TRUE)
	om_derived_invalidate_relation(target, relation_path, OM_READ_INCOMING, 0, TRUE)

/// Only entities that started a behaviour runtime pay for related change routing.
/proc/om_scheduled_wake_owned(datum/owner, slot_id, mask, membership)
	var/datum/object_model/behaviour_runtime/R = owner?.om_state?.behaviour_runtime
	if(!R)
		return
	for(var/path in R.active)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		for(var/list/input as anything in B.run_owned_inputs)
			if(input[1] == slot_id && (membership || (input[2] & mask)))
				R.wake(path)
				break

/proc/om_scheduled_wake_relation(datum/subject, relation_path, direction, mask, membership)
	var/datum/object_model/behaviour_runtime/R = subject?.om_state?.behaviour_runtime
	if(!R)
		return
	for(var/path in R.active)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		for(var/list/input as anything in B.run_relation_inputs)
			if(input[1] == relation_path && input[2] == direction && (membership || (input[3] & mask)))
				R.wake(path)
				break

/// Observation retains a derived view and causes changed effective values to
/// call the behaviour hook. That hook normally emits an existing typed event.
/datum/object_model/derived_watch
	var/datum/observer
	var/datum/subject
	var/behaviour_path

/datum/object_model/derived_watch/proc/start(datum/new_observer, datum/new_subject, new_path)
	if(!new_observer || QDELETED(new_observer) || !new_subject || QDELETED(new_subject))
		return FALSE
	if(!om_claim(new_observer, "om:derived_watch", src))
		return FALSE
	observer = new_observer
	subject = new_subject
	behaviour_path = new_path
	om_derived_read(subject, behaviour_path)
	var/datum/object_model/change_state/state = om_change_state_for(subject)
	var/list/entry = om_derived_entry(state, behaviour_path)
	entry[OM_DERIVED_OBSERVERS]++
	RegisterSignal(observer, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	if(subject != observer)
		RegisterSignal(subject, COMSIG_QDELETING, PROC_REF(on_endpoint_deleting))
	return TRUE

/datum/object_model/derived_watch/proc/on_endpoint_deleting(datum/source)
	SIGNAL_HANDLER
	qdel(src)

/datum/object_model/derived_watch/Destroy()
	var/datum/object_model/change_state/state = om_change_state_for(subject)
	var/list/entry = state?.views?[behaviour_path]
	if(entry)
		entry[OM_DERIVED_OBSERVERS] = max(0, entry[OM_DERIVED_OBSERVERS] - 1)
	if(observer && !QDELETED(observer))
		UnregisterSignal(observer, COMSIG_QDELETING)
	if(subject && subject != observer && !QDELETED(subject))
		UnregisterSignal(subject, COMSIG_QDELETING)
	observer = null
	subject = null
	behaviour_path = null
	return ..()

/proc/om_observe_derived(datum/observer, datum/subject, behaviour_path)
	var/datum/object_model/derived_watch/W = new
	if(!W.start(observer, subject, behaviour_path))
		qdel(W)
		return null
	return W
