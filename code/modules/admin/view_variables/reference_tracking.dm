#ifdef REFERENCE_TRACKING
#define REFSEARCH_RECURSE_LIMIT 64

/datum/proc/find_references(references_to_clear = INFINITY)
	if(usr?.client)
		if(rerun_ask(usr, "sure", PROC_REF(find_references), args, /datum/prompt/choice, question = "Running this will lock everything up for about 5 minutes.  Would you like to begin the search?", title = "Find References", choices = list("Yes", "No"), buttons = TRUE) != "Yes")
			return

#ifdef UNIT_TESTS
	if(!usr?.client && !dq_refsearch_allowed(src))
		return
	var/search_started = REALTIMEOFDAY
#endif
	src.references_to_clear = references_to_clear
	//this keeps the garbage collector from failing to collect objects being searched for in here
	SSgarbage.can_fire = FALSE

	_search_references(src)
	//restart the garbage collector
	SSgarbage.can_fire = TRUE
#ifdef UNIT_TESTS
	GLOB.dq_refsearch_spent_ds += REALTIMEOFDAY - search_started
#endif

// Declared in every build so unit_test.dm and DreamChecker see them; only test builds fill them.
GLOBAL_LIST_EMPTY(dq_refsearch_searched)
GLOBAL_LIST_EMPTY(dq_refsearch_type_counts)
GLOBAL_LIST_EMPTY(dq_refsearch_skipped)
GLOBAL_VAR_INIT(dq_refsearch_spent_ds, 0)

#ifdef UNIT_TESTS
/// Test builds: every automatic reference search (GC hard lookup, collapse
/// diagnostics) runs with FIND_REF_NO_CHECK_TICK and can freeze the world for
/// tens of seconds. Unbounded, a caller that keeps re-offering the same
/// object hangs the suite, so each object is searched once, each type at most
/// DQ_REFSEARCH_PER_TYPE times (once: a second search of the same leaking type repeats the first one's answer at ~5-40 s each), and all searches together get
/// DQ_REFSEARCH_BUDGET_DS of real time. Running out fails the run with a report
/// instead of hanging it.
#define DQ_REFSEARCH_PER_TYPE 1
#define DQ_REFSEARCH_BUDGET_DS (5 MINUTES)

/proc/dq_refsearch_allowed(datum/D)
	var/key = ref(D)
	if(GLOB.dq_refsearch_searched[key])
		log_reftracker("Skipping repeat search for references to [D.type] [key]: already searched once this run.")
		return FALSE
	if(GLOB.dq_refsearch_type_counts[D.type] >= DQ_REFSEARCH_PER_TYPE)
		GLOB.dq_refsearch_skipped[D.type]++
		log_reftracker("Skipping search for references to [D.type] [key]: type already searched [DQ_REFSEARCH_PER_TYPE] times.")
		return FALSE
	if(GLOB.dq_refsearch_spent_ds >= DQ_REFSEARCH_BUDGET_DS)
		GLOB.dq_refsearch_skipped[D.type]++
		var/message = "REF SEARCH budget exhausted ([GLOB.dq_refsearch_spent_ds / 10]s spent searching): skipped search for [D.type] [key]. Something keeps offering undeletable objects for reference searches; see the ## REF SEARCH lines in runtime.log."
		log_reftracker(message)
		log_test(message)
		GLOB.failed_any_test = TRUE
		return FALSE
	GLOB.dq_refsearch_searched[key] = TRUE
	GLOB.dq_refsearch_type_counts[D.type]++
	return TRUE

#undef DQ_REFSEARCH_PER_TYPE
#undef DQ_REFSEARCH_BUDGET_DS
#endif

/proc/_search_references(datum/source)
	log_reftracker("Beginning search for references to a [source.type], looking for [source.references_to_clear] refs.")

	var/starting_time = world.time
	//Time to search the whole game for our ref
	source.DoSearchVar(GLOB, "GLOB", starting_time) //globals
	log_reftracker("Finished searching globals")
	if(source.references_to_clear == 0)
		return

	//Yes we do actually need to do this. The searcher refuses to read weird lists
	//And global.vars is a really weird list
	var/global_vars = list()
	for(var/key in global.vars)
		global_vars[key] = global.vars[key]

	source.DoSearchVar(global_vars, "Native Global", starting_time)
	log_reftracker("Finished searching native globals")
	if(source.references_to_clear == 0)
		return

	for(var/datum/thing in world) //atoms (don't beleive its lies)
		source.DoSearchVar(thing, "World -> [thing.type]", starting_time)
		if(source.references_to_clear == 0)
			break
	log_reftracker("Finished searching atoms")
	if(source.references_to_clear == 0)
		return

	for(var/datum/thing) //datums
		source.DoSearchVar(thing, "Datums -> [thing.type]", starting_time)
		if(source.references_to_clear == 0)
			break
	log_reftracker("Finished searching datums")
	if(source.references_to_clear == 0)
		return

	//Warning, attempting to search clients like this will cause crashes if done on live. Watch yourself
#ifndef REFERENCE_DOING_IT_LIVE
	for(var/client/thing) //clients
		source.DoSearchVar(thing, "Clients -> [thing.type]", starting_time)
		if(source.references_to_clear == 0)
			break
	log_reftracker("Finished searching clients")
	if(source.references_to_clear == 0)
		return
#endif

	log_reftracker("Completed search for references to a [source.type].")

/datum/proc/DoSearchVar(potential_container, container_name, search_time, recursion_count, is_special_list)
	if(recursion_count >= REFSEARCH_RECURSE_LIMIT)
		log_reftracker("Recursion limit reached. [container_name]")
		return

	if(references_to_clear == 0)
		return

	//Check each time you go down a layer. This makes it a bit slow, but it won't effect the rest of the game at all
	#ifndef FIND_REF_NO_CHECK_TICK
	CHECK_TICK
	#endif

	if(isdatum(potential_container))
		var/datum/datum_container = potential_container
		if(datum_container.last_find_references == search_time)
			return

		datum_container.last_find_references = search_time
		var/list/vars_list = datum_container.vars

		var/is_atom = FALSE
		var/is_area = FALSE
		if(isatom(datum_container))
			is_atom = TRUE
			if(isarea(datum_container))
				is_area = TRUE
		for(var/varname in vars_list)
			var/variable = vars_list[varname]
			if(islist(variable))
				//Fun fact, vis_locs don't count for references
				if(varname == "vars" || (is_atom && (varname == "vis_locs" || varname == "overlays" || varname == "underlays" || varname == "filters" || varname == "verbs" || (is_area && varname == "contents"))))
					continue
				// We do this after the varname check to avoid area contents (reading it incures a world loop's worth of cost)
				if(!length(variable))
					continue
				DoSearchVar(variable,\
					"[container_name] [datum_container.ref_search_details()] -> [varname] (list)",\
					search_time,\
					recursion_count + 1,\
					/*is_special_list = */ is_atom && (varname == "contents" || varname == "vis_contents" || varname == "locs"))
			else if(variable == src)
				#ifdef REFERENCE_TRACKING_DEBUG
				if(SSgarbage.should_save_refs)
					if(!found_refs)
						found_refs = list()
					found_refs[varname] = TRUE
					continue //End early, don't want these logging
				else
					log_reftracker("Found [type] [text_ref(src)] in [datum_container.type]'s [datum_container.ref_search_details()] [varname] var. [container_name]")
				#else
				log_reftracker("Found [type] [text_ref(src)] in [datum_container.type]'s [datum_container.ref_search_details()] [varname] var. [container_name]")
				#endif
				references_to_clear -= 1
				if(references_to_clear == 0)
					log_reftracker("All references to [type] [text_ref(src)] found, exiting.")
					return
				continue

	else if(islist(potential_container))
		var/list/potential_cache = potential_container
		for(var/element_in_list in potential_cache)
			//Check normal sublists
			if(islist(element_in_list))
				if(length(element_in_list))
					DoSearchVar(element_in_list, "[container_name] -> [element_in_list] (list)", search_time, recursion_count + 1)
			//Check normal entrys
			else if(element_in_list == src)
				#ifdef REFERENCE_TRACKING_DEBUG
				if(SSgarbage.should_save_refs)
					if(!found_refs)
						found_refs = list()
					found_refs[potential_cache] = TRUE
					continue
				else
					log_reftracker("Found [type] [text_ref(src)] in list [container_name].")
				#else
				log_reftracker("Found [type] [text_ref(src)] in list [container_name].")
				#endif

				// This is dumb as hell I'm sorry
				// I don't want the garbage subsystem to count as a ref for the purposes of this number
				// If we find all other refs before it I want to early exit, and if we don't I want to keep searching past it
				var/ignore_ref = FALSE
				var/list/queues = SSgarbage.queues
				for(var/list/queue in queues)
					if(potential_cache in queue)
						ignore_ref = TRUE
						break
				if(ignore_ref)
					log_reftracker("[container_name] does not count as a ref for our count")
				else
					references_to_clear -= 1
				if(references_to_clear == 0)
					log_reftracker("All references to [type] [text_ref(src)] found, exiting.")
					return

			if(!isnum(element_in_list) && !is_special_list)
				// This exists to catch an error that throws when we access a special list
				// is_special_list is a hint, it can be wrong
				try
					var/assoc_val = potential_cache[element_in_list]
					//Check assoc sublists
					if(islist(assoc_val))
						if(length(assoc_val))
							DoSearchVar(potential_container[element_in_list], "[container_name]\[[element_in_list]\] -> [assoc_val] (list)", search_time, recursion_count + 1)
					//Check assoc entry
					else if(assoc_val == src)
						#ifdef REFERENCE_TRACKING_DEBUG
						if(SSgarbage.should_save_refs)
							if(!found_refs)
								found_refs = list()
							found_refs[potential_cache] = TRUE
							continue
						else
							log_reftracker("Found [type] [text_ref(src)] in list [container_name]\[[element_in_list]\]")
						#else
						log_reftracker("Found [type] [text_ref(src)] in list [container_name]\[[element_in_list]\]")
						#endif
						references_to_clear -= 1
						if(references_to_clear == 0)
							log_reftracker("All references to [type] [text_ref(src)] found, exiting.")
							return
				catch
					// So if it goes wrong we kill it
					is_special_list = TRUE
					log_reftracker("Curiosity: [container_name] lead to an error when acessing [element_in_list], what is it?")

#undef REFSEARCH_RECURSE_LIMIT
#endif

// Kept outside the ifdef so overrides are easy to implement

/// Return info about us for reference searching purposes
/// Will be logged as a representation of this datum if it's a part of a search chain
/datum/proc/ref_search_details()
	return text_ref(src)

/datum/callback/ref_search_details()
	return "[text_ref(src)] (obj: [target_object()] proc: [delegate] args: [json_encode(arguments)] user: [om_resolve(user) || "null"])"
