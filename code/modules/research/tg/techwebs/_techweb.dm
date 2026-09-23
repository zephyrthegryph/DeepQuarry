/**
 * # Techweb
 *
 * A datum representing a research techweb
 *
 * Techweb datums are meant to store unlocked research, being able to be stored
 * on research consoles, servers, and disks. They are NOT global.
 */
/datum/techweb
	///The id/name of the whole Techweb viewable to players.
	var/id = "Generic"
	/// Organization name, used for display
	var/organization = "Third-Party"

	/// Already unlocked and all designs are now available. Assoc list, id = TRUE
	var/list/researched_nodes
	/// Visible nodes, doesn't mean it can be researched. Assoc list, id = TRUE
	var/list/visible_nodes
	/// Nodes that can immediately be researched, all reqs met. assoc list, id = TRUE
	var/list/available_nodes
	/// Designs that are available for use. Assoc list, id = TRUE
	var/list/researched_designs
	/// Custom inserted designs like from disks that should survive recalculation.
	var/list/custom_designs
	/// Already boosted nodes that can't be boosted again. node id = path of boost object.
	var/list/boosted_nodes = list()
	/// Hidden nodes. id = TRUE. Used for unhiding nodes when requirements are met by removing the entry of the node.
	var/list/hidden_nodes
	/// List of items already deconstructed for research points, preventing infinite research point generation.
	var/list/deconstructed_items
	/// Available research points, type = number
	var/list/research_points
	/// Game logs of research nodes, "node_name" "node_cost" "node_researcher" "node_research_location"
	var/list/research_logs
	/// Current per-second production, used for display only.
	var/list/last_bitcoins
	/// Mutations discovered by genetics, this way they are shared and cant be destroyed by destroying a single console
	var/list/discovered_mutations
	/// Assoc list, id = number, 1 is available, 2 is all reqs are 1, so on
	var/list/tiers
	/// When >0, update_node_status() defers tier recomputation instead of running a
	/// full descendant BFS per call. Set of node datums whose tiers must be refreshed
	/// is accumulated in deferred_tier_roots and flushed once via flush_deferred_tiers().
	var/tier_recompute_deferred = 0
	/// Node datums queued for a deferred update_tiers() sweep; see tier_recompute_deferred.
	var/list/deferred_tier_roots
	/// This is a list of all incomplete experiment datums that are accessible for scientists to complete
	var/list/datum/experiment/available_experiments
	/// A list of all experiment datums that have been complete
	var/list/datum/experiment/completed_experiments
	/// Assoc list of all experiment datums that have been skipped, to tech point reward for completing them -
	/// That is, upon researching a node without completing its associated discounts, their experiments go here.
	/// Completing these experiments will have a refund.
	var/list/datum/experiment/skipped_experiment_types

	///All RD consoles connected to this individual techweb.
	var/list/obj/machinery/computer/rdconsole_tg/consoles_accessing
	///All research servers connected to this individual techweb.
	var/list/obj/machinery/rnd/server/techweb_servers

	///Boolean on whether the techweb should generate research points overtime.
	var/should_generate_points = FALSE
	///A multiplier applied to all research gain, cut in half if the Master server was sabotaged.
	var/income_modifier = 1
	///The amount of research points generated the techweb generated the latest time it generated.
	var/last_income

	/**
	 * Assoc list of relationships with various partners
	 * scientific_cooperation[partner_typepath] = relationship
	 */
	var/list/scientific_cooperation
	/**
	  * Assoc list of papers already published by the crew.
	  * published_papers[experiment_typepath][tier] = paper
	  * Filled with nulls on init, populated only on publication.
	*/
	var/list/published_papers
	/**
	  * Assoc list of nodes queued for automatic research when there are enough points available
	  * research_queue_nodes[node_id] = user_enqueued
	*/
	var/list/research_queue_nodes

/datum/techweb/New()
	SSresearch.techwebs += src
	for(var/i in SSresearch.techweb_nodes_starting)
		var/datum/techweb_node/DN = SSresearch.techweb_node_by_id(i)
		research_node(DN, TRUE, FALSE, FALSE)
	hidden_nodes = SSresearch.techweb_nodes_hidden.Copy()
	// initialize_published_papers()
	return ..()

/datum/techweb/Destroy()
	researched_nodes = null
	researched_designs = null
	available_nodes = null
	visible_nodes = null
	custom_designs = null
	SSresearch.techwebs -= src
	return ..()

/datum/techweb/proc/recalculate_nodes(recalculate_designs = FALSE, wipe_custom_designs = FALSE)
	var/list/datum/techweb_node/processing = list()
	for(var/id in researched_nodes)
		processing[id] = TRUE
	for(var/id in visible_nodes)
		processing[id] = TRUE
	for(var/id in available_nodes)
		processing[id] = TRUE
	if(recalculate_designs)
		researched_designs = LAZYCOPY(custom_designs)
		if(wipe_custom_designs)
			custom_designs = list()
	defer_tier_recompute()
	for(var/id in processing)
		update_node_status(SSresearch.techweb_node_by_id(id))
		CHECK_TICK
	flush_deferred_tiers()

/datum/techweb/proc/add_point_list(list/pointlist)
	for(var/i in pointlist)
		if((i in SSresearch.point_types) && pointlist[i] > 0)
			LAZYSET(research_points, i, FLOOR(LAZYACCESS(research_points, i) + pointlist[i], 0.1))

/datum/techweb/proc/add_points_all(amount)
	var/list/l = SSresearch.point_types.Copy()
	for(var/i in l)
		l[i] = amount
	add_point_list(l)

/datum/techweb/proc/remove_point_list(list/pointlist)
	for(var/i in pointlist)
		if((i in SSresearch.point_types) && pointlist[i] > 0)
			LAZYSET(research_points, i, FLOOR(max(0, LAZYACCESS(research_points, i) - pointlist[i]), 0.1))

/datum/techweb/proc/remove_points_all(amount)
	var/list/l = SSresearch.point_types.Copy()
	for(var/i in l)
		l[i] = amount
	remove_point_list(l)

/datum/techweb/proc/modify_point_list(list/pointlist)
	for(var/i in pointlist)
		if((i in SSresearch.point_types) && pointlist[i] != 0)
			LAZYSET(research_points, i, FLOOR(max(0, LAZYACCESS(research_points, i) + pointlist[i]), 0.1))

/datum/techweb/proc/modify_points_all(amount)
	var/list/l = SSresearch.point_types.Copy()
	for(var/i in l)
		l[i] = amount
	modify_point_list(l)

/datum/techweb/proc/copy_research_to(datum/techweb/receiver) //Adds any missing research to theirs.
	for(var/i in receiver.hidden_nodes)
		CHECK_TICK
		if(get_available_nodes()[i] || get_researched_nodes()[i] || get_visible_nodes()[i])
			LAZYREMOVE(receiver.hidden_nodes, i) //We can see it so let them see it too.
	for(var/i in researched_nodes - receiver.researched_nodes)
		CHECK_TICK
		receiver.research_node_id(i, TRUE, FALSE, FALSE)
	for(var/i in researched_designs - receiver.researched_designs)
		CHECK_TICK
		receiver.add_design_by_id(i)
	receiver.recalculate_nodes()

/datum/techweb/proc/copy()
	var/datum/techweb/returned = new()
	returned.researched_nodes = LAZYCOPY(researched_nodes)
	returned.visible_nodes = LAZYCOPY(visible_nodes)
	returned.available_nodes = LAZYCOPY(available_nodes)
	returned.researched_designs = LAZYCOPY(researched_designs)
	returned.hidden_nodes = LAZYCOPY(hidden_nodes)
	return returned

/datum/techweb/proc/get_visible_nodes() //The way this is set up is shit but whatever.
	return (visible_nodes || list()) - hidden_nodes

/datum/techweb/proc/get_available_nodes()
	return (available_nodes || list()) - hidden_nodes

/datum/techweb/proc/get_researched_nodes()
	return (researched_nodes || list()) - hidden_nodes

/datum/techweb/proc/add_point_type(type, amount)
	if(!(type in SSresearch.point_types) || (amount <= 0))
		return FALSE
	LAZYADDASSOC(research_points, type, amount)
	return TRUE

/datum/techweb/proc/modify_point_type(type, amount)
	if(!(type in SSresearch.point_types))
		return FALSE
	LAZYSET(research_points, type, max(0, LAZYACCESS(research_points, type) + amount))
	return TRUE

/datum/techweb/proc/remove_point_type(type, amount)
	if(!(type in SSresearch.point_types) || (amount <= 0))
		return FALSE
	LAZYSET(research_points, type, max(0, LAZYACCESS(research_points, type) - amount))
	return TRUE

/**
 * add_design_by_id
 * The main way to add add designs to techweb
 * Uses the techweb node's ID
 * Args:
 * id - the ID of the techweb node to research
 * custom - Boolean on whether the node should also be added to custom_designs
 * add_to - A custom list to add the node to, overwriting research_designs.
 */
/datum/techweb/proc/add_design_by_id(id, custom = FALSE, list/add_to)
	return add_design(SSresearch.techweb_design_by_id(id), custom, add_to)

/datum/techweb/proc/add_design(datum/design_techweb/design, custom = FALSE, list/add_to)
	if(!istype(design))
		return FALSE
	// Invariant: every design added to a techweb must be a registered global datum.
	// An unregistered design ID means SSresearch state is inconsistent with what is being unlocked.
	if(design.id != DESIGN_ID_IGNORE && !SSresearch.techweb_designs[design.id])
		CRASH("add_design called with unregistered design ID '[design.id]' ([design.type]) on techweb '[id]' — design is not in SSresearch.techweb_designs")
	SEND_SIGNAL(src, COMSIG_TECHWEB_ADD_DESIGN, design, custom)
	if(custom)
		LAZYSET(custom_designs, design.id, TRUE)

	if(add_to)
		add_to[design.id] = TRUE
	else
		LAZYSET(researched_designs, design.id, TRUE)

	for(var/node_id as anything in design.unlocked_by)
		LAZYREMOVE(hidden_nodes, node_id)

	return TRUE

/datum/techweb/proc/remove_design_by_id(id, custom = FALSE)
	return remove_design(SSresearch.techweb_design_by_id(id), custom)

/datum/techweb/proc/remove_design(datum/design_techweb/design, custom = FALSE)
	if(!istype(design))
		return FALSE
	if(LAZYACCESS(custom_designs, design.id) && !custom)
		return FALSE
	SEND_SIGNAL(src, COMSIG_TECHWEB_REMOVE_DESIGN, design, custom)
	LAZYREMOVE(custom_designs, design.id)
	LAZYREMOVE(researched_designs, design.id)
	return TRUE

/datum/techweb/proc/get_point_total(list/pointlist)
	for(var/i in pointlist)
		. += pointlist[i]

/datum/techweb/proc/can_afford(list/pointlist)
	for(var/i in pointlist)
		if(LAZYACCESS(research_points, i) < pointlist[i])
			return FALSE
	return TRUE

/**
 * Checks if all experiments have been completed for a given node on this techweb
 *
 * Arguments:
 * * node - the node to check
 */
/datum/techweb/proc/have_experiments_for_node(datum/techweb_node/node)
	. = TRUE
	for (var/experiment_type in node.required_experiments)
		if (!LAZYACCESS(completed_experiments, experiment_type))
			return FALSE

/**
 * Checks if a node can be unlocked on this techweb, having the required points and experiments
 *
 * Arguments:
 * * node - the node to check
 */
/datum/techweb/proc/can_unlock_node(datum/techweb_node/node)
	return can_afford(node.get_price(src)) && have_experiments_for_node(node)

/**
 * Adds an experiment to this techweb by its type, ensures that no duplicates are added.
 *
 * Arguments:
 * * experiment_type - the type of the experiment to add
 */
/datum/techweb/proc/add_experiment(experiment_type)
	. = TRUE
	// check active experiments for experiment of this type
	for (var/available_experiment in available_experiments)
		var/datum/experiment/experiment = available_experiment
		if (experiment.type == experiment_type)
			return FALSE
	// check completed experiments for experiments of this type
	for (var/completed_experiment in completed_experiments)
		var/datum/experiment/experiment = completed_experiment
		if (experiment == experiment_type)
			return FALSE
	LAZYADD(available_experiments, new experiment_type(src))

/**
 * Adds a list of experiments to this techweb by their types, ensures that no duplicates are added.
 *
 * Arguments:
 * * experiment_list - the list of types of experiments to add
 */
/datum/techweb/proc/add_experiments(list/experiment_list)
	. = TRUE
	for (var/datum/experiment/experiment as anything in experiment_list)
		. = . && add_experiment(experiment)

/**
 * Notifies the techweb that an experiment has been completed, updating internal state of the techweb to reflect this.
 *
 * Arguments:
 * * completed_experiment - the experiment which was completed
 */
/datum/techweb/proc/complete_experiment(datum/experiment/completed_experiment)
	LAZYREMOVE(available_experiments, completed_experiment)
	LAZYSET(completed_experiments, completed_experiment.type, completed_experiment)

	var/result_text = "[completed_experiment] has been completed"
	var/refund = LAZYACCESS(skipped_experiment_types, completed_experiment.type) || 0
	if(refund > 0)
		add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = refund))
		result_text += ", refunding [refund] points"
		// Nothing more to gain here, but we keep it in the list to prevent double dipping
		LAZYSET(skipped_experiment_types, completed_experiment.type, -1)
	var/points_rewarded
	if(completed_experiment.points_reward)
		add_point_list(completed_experiment.points_reward)
		points_rewarded = ",[refund > 0 ? " and" : ""] rewarding [completed_experiment.get_points_reward_text()]"
		result_text += points_rewarded
	result_text += "!"

	log_research("[completed_experiment.name] ([completed_experiment.type]) has been completed on techweb [id]/[organization][refund ? ", refunding [refund] points" : ""][points_rewarded].")
	return result_text

/datum/techweb/proc/printout_points()
	return techweb_point_display_generic(research_points || list())

/datum/techweb/proc/enqueue_node(id, mob/user)
	var/queue_first = FALSE
	if(istype(user, /mob/living/carbon/human))
		var/mob/living/carbon/human/human_user = user
		var/list/access = human_user.wear_id?.GetAccess()
		if(ACCESS_RD in access)
			queue_first = TRUE

	if(id in research_queue_nodes)
		if(queue_first)
			LAZYREMOVE(research_queue_nodes, id) // Remove to be able to place first
		else
			return FALSE

	for(var/node_id in research_queue_nodes)
		if(LAZYACCESS(research_queue_nodes, node_id) == user)
			LAZYREMOVE(research_queue_nodes, node_id)

	if (queue_first)
		LAZYINITLIST(research_queue_nodes); research_queue_nodes.Insert(1, id)
	LAZYSET(research_queue_nodes, id, user)

	return TRUE

/datum/techweb/proc/dequeue_node(id, mob/user)
	if(!(id in research_queue_nodes))
		return FALSE
	if(LAZYACCESS(research_queue_nodes, id) != user)
		return FALSE

	LAZYREMOVE(research_queue_nodes, id)

	return TRUE

/datum/techweb/proc/research_node_id(id, force, auto_update_points, get_that_dosh_id, atom/research_source)
	return research_node(SSresearch.techweb_node_by_id(id), force, auto_update_points, get_that_dosh_id, research_source)

/datum/techweb/proc/research_node(datum/techweb_node/node, force = FALSE, auto_adjust_cost = TRUE, get_that_dosh = TRUE, atom/research_source)
	if(!istype(node))
		return FALSE
	// Invariant: every node researched must be a registered global datum.
	// An unregistered node means SSresearch state is inconsistent — error early.
	if(node.id != "ERROR" && !SSresearch.techweb_nodes[node.id])
		CRASH("research_node called with unregistered node '[node.id]' ([node.type]) on techweb '[id]' — node is not in SSresearch.techweb_nodes")
	// Defer the per-node tier BFS until the whole unlock batch below has run, so the
	// many overlapping update_node_status() calls only trigger one coalesced sweep.
	defer_tier_recompute()
	update_node_status(node)
	if(!force)
		if(!LAZYACCESS(available_nodes, node.id) || (auto_adjust_cost && (!can_afford(node.get_price(src)))) || !have_experiments_for_node(node))
			flush_deferred_tiers()
			return FALSE
	var/log_message = "[id]/[organization] researched node [node.id]"
	if(auto_adjust_cost)
		var/list/node_cost = node.get_price(src)
		remove_point_list(node_cost)
		log_message += " at the cost of [json_encode(node_cost)]"

	//Add to our researched list
	LAZYSET(researched_nodes, node.id, TRUE)

	// Track any experiments we skipped relating to this
	for(var/missed_experiment in node.discount_experiments)
		if(LAZYACCESS(completed_experiments, missed_experiment) || LAZYACCESS(skipped_experiment_types, missed_experiment))
			continue
		LAZYSET(skipped_experiment_types, missed_experiment, node.discount_experiments[missed_experiment])

	// Gain the experiments from the new node
	for(var/id in node.unlock_ids)
		LAZYSET(visible_nodes, id, TRUE)
		var/datum/techweb_node/unlocked_node = SSresearch.techweb_node_by_id(id)
		if (length(unlocked_node.required_experiments))
			add_experiments(unlocked_node.required_experiments)
		if (length(unlocked_node.discount_experiments))
			add_experiments(unlocked_node.discount_experiments)
		update_node_status(unlocked_node)

	// Gain more new experiments
	if (length(node.experiments_to_unlock))
		add_experiments(node.experiments_to_unlock)

	// Unlock what the research actually unlocks
	for(var/id in node.design_ids)
		add_design_by_id(id)
	update_node_status(node)

	// Avoid logging the same 300+ lines at the beginning of every round
	if (!isnull(Master) && Master.current_runlevel == RUNLEVEL_GAME)
		log_research(log_message)

	// Dequeue
	if(node.id in research_queue_nodes)
		LAZYREMOVE(research_queue_nodes, node.id)

	flush_deferred_tiers()
	return TRUE

/datum/techweb/proc/unresearch_node_id(id)
	return unresearch_node(SSresearch.techweb_node_by_id(id))

/datum/techweb/proc/unresearch_node(datum/techweb_node/node)
	if(!istype(node))
		return FALSE
	LAZYREMOVE(researched_nodes, node.id)
	recalculate_nodes(TRUE) //Fully rebuild the tree.

/// Boosts a techweb node.
/datum/techweb/proc/boost_techweb_node(datum/techweb_node/node, list/pointlist)
	if(!istype(node))
		return FALSE
	LAZYINITLIST(boosted_nodes[node.id])
	for(var/point_type in pointlist)
		boosted_nodes[node.id][point_type] = max(boosted_nodes[node.id][point_type], pointlist[point_type])
	unhide_node(node)
	update_node_status(node)
	return TRUE

///Removes a node from the hidden_nodes list, making it viewable and researchable (if no experiments are required).
/datum/techweb/proc/unhide_node(datum/techweb_node/node)
	if(!istype(node))
		return FALSE
	LAZYREMOVE(hidden_nodes, node.id)
	///Make it available if the prereq ids are already researched
	update_node_status(node)
	return TRUE

/datum/techweb/proc/update_tiers(datum/techweb_node/base)
	var/list/current = list(base)
	while (current.len)
		var/list/next = list()
		for (var/node_ in current)
			var/datum/techweb_node/node = node_
			var/tier = 0
			if (!LAZYACCESS(researched_nodes, node.id)) // researched is tier 0
				for (var/id in node.prereq_ids)
					var/prereq_tier = LAZYACCESS(tiers, id)
					tier = max(tier, prereq_tier + 1)

			if (tier != tiers[node.id])
				LAZYSET(tiers, node.id, tier)
				for (var/id in node.unlock_ids)
					next += SSresearch.techweb_node_by_id(id)
		current = next

/// Begin a batch during which update_node_status() defers its per-node update_tiers()
/// BFS. Nest-safe via a counter; pair every call with flush_deferred_tiers().
/datum/techweb/proc/defer_tier_recompute()
	tier_recompute_deferred++

/// End a deferred-tier batch. When the outermost batch closes, run update_tiers()
/// once per queued root, coalescing the redundant overlapping BFS sweeps that would
/// otherwise run on every update_node_status() call during a research_node() batch.
/datum/techweb/proc/flush_deferred_tiers()
	if(tier_recompute_deferred <= 0)
		return
	tier_recompute_deferred--
	if(tier_recompute_deferred > 0)
		return
	if(!length(deferred_tier_roots))
		return
	var/list/roots = deferred_tier_roots
	deferred_tier_roots = list()
	for(var/datum/techweb_node/root as anything in roots)
		update_tiers(root)

/datum/techweb/proc/update_node_status(datum/techweb_node/node)
	var/researched = FALSE
	var/available = FALSE
	var/visible = FALSE
	if(LAZYACCESS(researched_nodes, node.id))
		researched = TRUE
	var/needed = length(node.prereq_ids)
	for(var/id in node.prereq_ids)
		if(LAZYACCESS(researched_nodes, id))
			visible = TRUE
			needed--
	if(!needed)
		available = TRUE
	LAZYREMOVE(researched_nodes, node.id)
	LAZYREMOVE(available_nodes, node.id)
	LAZYREMOVE(visible_nodes, node.id)
	if(LAZYACCESS(hidden_nodes, node.id)) //Hidden.
		return
	if(researched)
		LAZYSET(researched_nodes, node.id, TRUE)
		for(var/id in node.design_ids - researched_designs)
			add_design(SSresearch.techweb_design_by_id(id))
	else
		if(available)
			LAZYSET(available_nodes, node.id, TRUE)
		else
			if(visible)
				LAZYSET(visible_nodes, node.id, TRUE)
	if(tier_recompute_deferred)
		LAZYSET(deferred_tier_roots, node, TRUE) // Coalesced and flushed by flush_deferred_tiers().
	else
		update_tiers(node)

//Laggy procs to do specific checks, just in case. Don't use them if you can just use the vars that already store all this!
/datum/techweb/proc/designHasReqs(datum/design_techweb/D)
	for(var/i in researched_nodes)
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(i)
		if(LAZYACCESS(N.design_ids, D.id))
			return TRUE
	return FALSE

/datum/techweb/proc/isDesignResearched(datum/design_techweb/D)
	return isDesignResearchedID(D.id)

/datum/techweb/proc/isDesignResearchedID(id)
	return LAZYACCESS(researched_designs, id)? SSresearch.techweb_design_by_id(id) : FALSE

/datum/techweb/proc/isNodeResearched(datum/techweb_node/N)
	return isNodeResearchedID(N.id)

/datum/techweb/proc/isNodeResearchedID(id)
	return LAZYACCESS(researched_nodes, id)? SSresearch.techweb_node_by_id(id) : FALSE

/datum/techweb/proc/isNodeVisible(datum/techweb_node/N)
	return isNodeResearchedID(N.id)

/datum/techweb/proc/isNodeVisibleID(id)
	return LAZYACCESS(visible_nodes, id)? SSresearch.techweb_node_by_id(id) : FALSE

/datum/techweb/proc/isNodeAvailable(datum/techweb_node/N)
	return isNodeAvailableID(N.id)

/datum/techweb/proc/isNodeAvailableID(id)
	return LAZYACCESS(available_nodes, id)? SSresearch.techweb_node_by_id(id) : FALSE

/// Fill published_papers with nulls.

/// Publish the paper into our techweb. Cancel if we are not allowed to.

// 	// If we haven't published a paper in the same topic ...
// 	if(locate(paper_to_add.experiment_path) in published_papers[paper_to_add.experiment_path])
// 		return TRUE
// 	// Quickly add and complete it.
// 	// PS: It's also possible to use add_experiment() together with a list/available_experiments check
// 	// to determine if we need to run all this, but this pretty much does the same while only needing one evaluation.

// 	add_experiment(paper_to_add.experiment_path)

// 	for (var/datum/experiment/experiment as anything in available_experiments)
// 		if(experiment.type != paper_to_add.experiment_path)
// 			continue

// 	return TRUE
