
/datum/ai_law
	var/law = ""
	var/index = 0

/datum/ai_law/New(law, index)
	src.law = law
	src.index = index

/datum/ai_law/proc/get_index()
	return index

/datum/ai_law/ion/get_index()
	return ionnum()

/datum/ai_law/zero/get_index()
	return 0

/datum/ai_laws
	/// The name of the lawset
	var/name = "Unknown Laws"
	var/law_header = "Prime Directives"
	var/selectable = 0
	var/datum/ai_law/zero/zeroth_law = null
	var/datum/ai_law/zero/zeroth_law_borg = null
	var/list/datum/ai_law/inherent_laws = list() // ALLOW(instance_list): d: per law set; every silicon has inherent laws
	var/list/datum/ai_law/supplied_laws = list() // ALLOW(instance_list): d: per law set, edited through the law procs; one per silicon
	var/list/datum/ai_law/ion/ion_laws = list() // ALLOW(instance_list): d: per law set, edited through the law procs; one per silicon
	/// Derived order of the laws this set owns: a relation list view, rebuilt by sort_laws().
	var/list/datum/ai_law/sorted_laws

	var/state_zeroth = 0
	var/list/state_ion = list() // ALLOW(instance_list): d: per law set, written through the internal law procs; one per silicon
	var/list/state_inherent = list() // ALLOW(instance_list): d: per law set, written through the internal law procs; one per silicon
	var/list/state_supplied = list() // ALLOW(instance_list): d: per law set, written through get/set_state_internal(); one per silicon

CAPABILITIES(/datum/ai_laws)
	ref_many(nameof(sorted_laws))
	owns_one(nameof(zeroth_law), /datum/ai_law/zero)
	owns_one(nameof(zeroth_law_borg), /datum/ai_law/zero)
	owns_many(nameof(inherent_laws), /datum/ai_law)
	owns_many(nameof(ion_laws), /datum/ai_law/ion)
	owns_many(nameof(supplied_laws))

/datum/ai_laws/New()
	..()
	sort_laws()

/* General ai_law functions */
/datum/ai_laws/proc/all_laws()
	sort_laws()
	return sorted_laws || list()

/datum/ai_laws/proc/laws_to_state()
	sort_laws()
	var/list/statements = new()
	for(var/datum/ai_law/law in sorted_laws)
		if(get_state_law(law))
			statements += law

	return statements

/datum/ai_laws/proc/sort_laws()
	if(length(sorted_laws))
		return

	for(var/ion_law in ion_laws)
		rel_add(src, nameof(sorted_laws), ion_law)

	if(zeroth_law)
		rel_add(src, nameof(sorted_laws), zeroth_law)

	var/index = 1
	for(var/datum/ai_law/inherent_law in inherent_laws)
		inherent_law.index = index++
		if(length(supplied_laws) < inherent_law.index || !istype(supplied_laws[inherent_law.index], /datum/ai_law))
			rel_add(src, nameof(sorted_laws), inherent_law)

	for(var/datum/ai_law/AL in supplied_laws)
		if(istype(AL))
			rel_add(src, nameof(sorted_laws), AL)

/datum/ai_laws/proc/sync(mob/living/silicon/S, full_sync = 1)
	// Add directly to laws to avoid log-spam
	S.sync_zeroth(zeroth_law, zeroth_law_borg)

	if(full_sync || length(ion_laws))
		S.laws.clear_ion_laws()
	if(full_sync || length(inherent_laws))
		S.laws.clear_inherent_laws()
	if(full_sync || length(supplied_laws))
		S.laws.clear_supplied_laws()

	for (var/datum/ai_law/law in ion_laws)
		S.laws.add_ion_law(law.law)
	for (var/datum/ai_law/law in inherent_laws)
		S.laws.add_inherent_law(law.law)
	for (var/datum/ai_law/law in supplied_laws)
		if(law)
			S.laws.add_supplied_law(law.index, law.law)


/mob/living/silicon/proc/sync_zeroth(datum/ai_law/zeroth_law, datum/ai_law/zeroth_law_borg)
	if (!is_malf_or_traitor(src))
		if(zeroth_law_borg)
			laws.set_zeroth_law(zeroth_law_borg.law)
		else if(zeroth_law)
			laws.set_zeroth_law(zeroth_law.law)

/mob/living/silicon/ai/sync_zeroth(datum/ai_law/zeroth_law, datum/ai_law/zeroth_law_borg)
	if(zeroth_law)
		laws.set_zeroth_law(zeroth_law.law, zeroth_law_borg ? zeroth_law_borg.law : null)

/****************
*	Add Laws	*
****************/
/datum/ai_laws/proc/set_zeroth_law(law, law_borg = null)
	if(!law)
		return

	rel_set(src, nameof(zeroth_law), new /datum/ai_law/zero(law))
	if(law_borg) //Making it possible for slaved borgs to see a different law 0 than their AI. --NEO
		rel_set(src, nameof(zeroth_law_borg), new /datum/ai_law/zero(law_borg))
	else
		rel_clear(src, nameof(zeroth_law_borg))
	rel_clear(src, nameof(sorted_laws))

/datum/ai_laws/proc/add_ion_law(law)
	if(!law)
		return

	for(var/datum/ai_law/AL in ion_laws)
		if(AL.law == law)
			return

	var/new_law = new/datum/ai_law/ion(law)
	rel_add(src, nameof(ion_laws), new_law)
	if(state_ion.len < length(ion_laws))
		state_ion += 1

	rel_clear(src, nameof(sorted_laws))

/datum/ai_laws/proc/add_inherent_law(law)
	if(!law)
		return

	for(var/datum/ai_law/AL in inherent_laws)
		if(AL.law == law)
			return

	var/new_law = new/datum/ai_law/inherent(law)
	rel_add(src, nameof(inherent_laws), new_law)
	if(state_inherent.len < length(inherent_laws))
		state_inherent += 1

	rel_clear(src, nameof(sorted_laws))

/datum/ai_laws/proc/add_supplied_law(number, law)
	if(!law)
		return

	if(length(supplied_laws) >= number)
		var/datum/ai_law/existing_law = supplied_laws[number]
		if(existing_law && existing_law.law == law)
			return

	if(length(supplied_laws) >= number && supplied_laws[number])
		delete_law(supplied_laws[number])

	if(!islist(supplied_laws))
		supplied_laws = list() // ALLOW(ownership): an empty owned list, padded below
	while (length(src.supplied_laws) < number)
		supplied_laws += "" // ALLOW(ownership): empty law slots (not entities); rel_add() would dedup them
		if(state_supplied.len < length(supplied_laws))
			state_supplied += 1

	var/new_law = new/datum/ai_law/supplied(law, number)
	rel_add(src, nameof(supplied_laws), new_law, number)
	if(state_supplied.len < length(supplied_laws))
		state_supplied += 1

	rel_clear(src, nameof(sorted_laws))

/****************
*	Remove Laws	*
*****************/
/datum/ai_laws/proc/delete_law(datum/ai_law/law)
	if(istype(law))
		law.delete_law(src)

/datum/ai_law/proc/delete_law(datum/ai_laws/laws)

/datum/ai_law/zero/delete_law(datum/ai_laws/laws)
	laws.clear_zeroth_laws()

/datum/ai_law/ion/delete_law(datum/ai_laws/laws)
	laws.internal_delete_law("ion_laws", laws.state_ion, src)

/datum/ai_law/inherent/delete_law(datum/ai_laws/laws)
	laws.internal_delete_law("inherent_laws", laws.state_inherent, src)

/datum/ai_law/supplied/delete_law(datum/ai_laws/laws)
	var/index = laws.supplied_laws.Find(src)
	if(index)
		rel_add(laws, nameof(laws.supplied_laws), "", index)
		laws.state_supplied[index] = 1

/// Deletes `law` from this set's owned law list `var_name`, shifting its state flags down.
/datum/ai_laws/proc/internal_delete_law(var_name, list/state, datum/ai_law/law)
	var/list/laws = vars[var_name]
	var/index = laws?.Find(law)
	if(index)
		own_remove(src, var_name, law)
		for(index, index < state.len, index++)
			state[index] = state[index+1]
	rel_clear(src, nameof(sorted_laws))

/****************
*	Clear Laws	*
****************/
/datum/ai_laws/proc/clear_zeroth_laws()
	rel_clear(src, nameof(zeroth_law))
	rel_clear(src, nameof(zeroth_law_borg))

/datum/ai_laws/proc/clear_ion_laws()
	rel_clear(src, nameof(ion_laws))
	rel_clear(src, nameof(sorted_laws))

/datum/ai_laws/proc/clear_inherent_laws()
	rel_clear(src, nameof(inherent_laws))
	rel_clear(src, nameof(sorted_laws))

/datum/ai_laws/proc/clear_supplied_laws()
	rel_clear(src, nameof(supplied_laws))
	rel_clear(src, nameof(sorted_laws))

/datum/ai_laws/proc/get_formatted_laws()
	sort_laws()
	var/list/law_block = list()
	for(var/datum/ai_law/law in sorted_laws)
		if(law == zeroth_law_borg)
			continue
		if(law == zeroth_law)
			law_block += span_info(span_red("[law.get_index()]. [law.law]"))
		else
			law_block += span_infoplain("[law.get_index()]. [law.law]")
	return examine_block(law_block.Join("\n"))

/datum/ai_laws/proc/show_laws(who)
	sort_laws()
	for(var/datum/ai_law/law in sorted_laws)
		if(law == zeroth_law_borg)
			continue
		if(law == zeroth_law)
			to_chat(who, span_info(span_red("[law.get_index()]. [law.law]")))
		else
			to_chat(who, span_infoplain("[law.get_index()]. [law.law]"))

/********************
*	Stating Laws	*
********************/
/********
*	Get	*
********/
/datum/ai_laws/proc/get_state_law(datum/ai_law/law)
	return law.get_state_law(src)

/datum/ai_law/proc/get_state_law(datum/ai_laws/laws)

/datum/ai_law/zero/get_state_law(datum/ai_laws/laws)
	if(src == laws.zeroth_law)
		return laws.state_zeroth

/datum/ai_law/ion/get_state_law(datum/ai_laws/laws)
	return laws.get_state_internal(laws.ion_laws, laws.state_ion, src)

/datum/ai_law/inherent/get_state_law(datum/ai_laws/laws)
	return laws.get_state_internal(laws.inherent_laws, laws.state_inherent, src)

/datum/ai_law/supplied/get_state_law(datum/ai_laws/laws)
	return laws.get_state_internal(laws.supplied_laws, laws.state_supplied, src)

/datum/ai_laws/proc/get_state_internal(list/datum/ai_law/laws, list/state, list/datum/ai_law/law)
	var/index = laws.Find(law)
	if(index)
		return state[index]
	return 0

/********
*	Set	*
********/
/datum/ai_laws/proc/set_state_law(datum/ai_law/law, state)
	law.set_state_law(src, state)

/datum/ai_law/proc/set_state_law(datum/ai_law/law, state)

/datum/ai_law/zero/set_state_law(datum/ai_laws/laws, state)
	if(src == laws.zeroth_law)
		laws.state_zeroth = state

/datum/ai_law/ion/set_state_law(datum/ai_laws/laws, state)
	laws.set_state_law_internal(laws.ion_laws, laws.state_ion, src, state)

/datum/ai_law/inherent/set_state_law(datum/ai_laws/laws, state)
	laws.set_state_law_internal(laws.inherent_laws, laws.state_inherent, src, state)

/datum/ai_law/supplied/set_state_law(datum/ai_laws/laws, state)
	laws.set_state_law_internal(laws.supplied_laws, laws.state_supplied, src, state)

/datum/ai_laws/proc/set_state_law_internal(list/datum/ai_law/laws, list/state, list/datum/ai_law/law, do_state)
	var/index = laws.Find(law)
	if(index)
		state[index] = do_state



/datum/ai_laws/declared_cache_vars()
	var/list/L = ..()
	L = L ? L.Copy() : list()
	L["sorted_laws"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	return L
