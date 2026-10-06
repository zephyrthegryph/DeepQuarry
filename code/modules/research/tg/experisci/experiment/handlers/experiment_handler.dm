/**
 * # Experiment Handler
 *
 * The owned state datum for interacting with experiments from a connected techweb (was the
 * experiment_handler component). It is generic and works on any movable holding it in its
 * `experiment_handler` var; create it with `new /datum/experiment_handler(holder, ...)`.
 * It observes the holder's events and actions with observe().
 */
CAPABILITIES(/datum/experiment_handler)
	op("clear_server", ui_act(), then(PROC_REF(ui_act_clear_server)))
	op("clear_experiment", ui_act(), then(PROC_REF(ui_act_clear_experiment)))
	interface("ExperimentConfigure")
	op("select_server", ui_act("select_server", arg("ref", schema_ref(/datum/techweb))), then(PROC_REF(ui_act_select_server)))
	op("select_experiment", ui_act("select_experiment", arg("ref", schema_ref(/datum/experiment))), then(PROC_REF(ui_act_select_experiment)))
	op("start_experiment_callback", ui_act("start_experiment_callback"), then(PROC_REF(ui_act_start_experiment_callback)))

/datum/experiment_handler
	/// The movable this handler belongs to.
	var/atom/movable/owner
	/// Holds the currently linked techweb to get experiments from
	var/tmp/datum/techweb/linked_web_static
	/// Holds the currently selected experiment
	var/tmp/datum/experiment/selected_experiment
	/// Holds the list of types of experiments that this experiment_handler can interact with
	var/list/allowed_experiments
	/// Holds the list of types of experiments that this experimennt_handler should NOT interact with
	var/list/blacklisted_experiments
	/// A set of optional experiment traits (see defines) that are disallowed for any experiments
	var/disallowed_traits
	/// Additional configuration flags for how the experiment_handler operates
	var/config_flags
	/// Callback that, when supplied, can be called from the UI
	var/list/start_experiment_spec // an om_callable() spec, run with the selected experiment

/// The experiment handler of this movable, if it has one. Owned: deleted with it.
/// Not saved: the holder's Initialize() makes a fresh handler; the selected experiment is session state.
/atom/movable/var/tmp/datum/experiment_handler/experiment_handler

/**
 * Creates the experiment handler of a movable
 *
 * Arguments:
 * * new_owner - The movable that holds this handler
 * * allowed_experiments - The list of /datum/experiment types that can be performed with this handler
 * * blacklisted_experiments - The list of /datum/experiment types that explicitly cannot be performed with this handler
 * * config_mode - The define that determines how the experiment_handler should display the configuration UI
 * * disallowed_traits - Flags that control what experiment traits are blacklisted by this experiment handler
 * * config_flags - Flags that control the operational behaviour of the experiment handler, see experiment defines
 * * start_experiment_spec - When provided (an om_callable() spec) adds a UI button to use it to the start the experiment
 * * experiment_events - list(event path = handler proc ref) hooked on the owner
 */
/datum/experiment_handler/New(atom/movable/new_owner,
	allowed_experiments = list(),
	blacklisted_experiments = list(),
	config_mode = EXPERIMENT_CONFIG_ATTACKSELF,
	disallowed_traits = null,
	config_flags = null,
	list/start_experiment_spec = null,
	list/experiment_events
)
	. = ..()
	if(!ismovable(new_owner))
		log_runtime("experiment_handler: created for a non-movable ([new_owner]); discarded")
		spent(src)
		return
	// The owner adopts us; its previous handler is deleted by rel_set().
	rel_set(src, nameof(/datum/action_group::owner), new_owner)
	rel_set(new_owner, nameof(/atom/movable::experiment_handler), src)

	src.allowed_experiments = allowed_experiments
	src.blacklisted_experiments = blacklisted_experiments
	src.disallowed_traits = disallowed_traits
	src.config_flags = config_flags
	src.start_experiment_spec = start_experiment_spec

	for(var/event_path in experiment_events)
		if(ispath(event_path, /datum/notice))
			observe(owner, event_path, src, then(experiment_events[event_path]))
		else
			// An action (the handheld scanner's pre_attack) can be taken over: the handler answers HOOK_DECLINE to let it go on.
			observe(owner, event_path, src, instead(then(experiment_events[event_path])))

	// Determine UI display mode
	switch(config_mode)
		if(EXPERIMENT_CONFIG_ATTACKSELF)
			observe(owner, /datum/notice/attack_self, src, then(PROC_REF(on_config_event)))
		if(EXPERIMENT_CONFIG_ALTCLICK)
			observe(owner, /datum/notice/click_alt, src, then(PROC_REF(on_config_event)))
		if(EXPERIMENT_CONFIG_UI)
			observe(owner, /datum/notice/ui_act, src, then(PROC_REF(ui_handle_experiment)))

	// Auto connect to the first visible techweb (useful for always active handlers)
	// Note this won't work at the moment for non-machines that have been included
	// on the map as the servers aren't initialized when the non-machines are initializing
	if (!(config_flags & EXPERIMENT_CONFIG_NO_AUTOCONNECT))
		var/datum/techweb/connected_web
		CONNECT_TO_RND_SERVER_ROUNDSTART(connected_web, owner)
		linked_web_static = connected_web

	join_registries()

REGISTRY_MEMBERSHIP(/datum/experiment_handler, REGISTRY_EXPERIMENT_HANDLERS)

/**
 * Hooks on attack to try and run an experiment (When using a handheld handler)
 */
/datum/experiment_handler/proc/try_run_handheld_experiment(datum/act/pre_attack/swing)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/target = swing.target_
	var/mob/user = swing.user
	var/datum/source = swing.target
	if (!should_run_handheld_experiment(source, target, user))
		return HOOK_DECLINE
	try_run_handheld_experiment_async(source, target, user)
	return TRUE

/**
 * Checks that an experiment can be run using the provided target, used for preventing the cancellation of the attack chain inappropriately
 */
/datum/experiment_handler/proc/should_run_handheld_experiment(datum/source, atom/target, mob/user)
	// Check that there is actually an experiment selected
	if (selected_experiment() == null && !(config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE))
		return
	if (!linked_web())
		return

	// Determine if this experiment is actionable with this target
	var/list/arguments = list(src)
	arguments = args.len > 1 ? arguments + args.Copy(2) : arguments
	if (config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE)
		for (var/datum/experiment/experiment in linked_web().available_experiments)
			if (experiment.actionable(arglist(arguments)))
				return TRUE
	else
		return selected_experiment().actionable(arglist(arguments))

/**
 * This proc exists because Jared Fogle really likes async
 */
/datum/experiment_handler/proc/try_run_handheld_experiment_async(datum/source, atom/target, mob/user)
	if (selected_experiment() == null && !(config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE))
		if(!(config_flags & EXPERIMENT_CONFIG_SILENT_FAIL))
			to_chat(user, span_notice("You do not have an experiment selected!"))
		return
	om_task_start(/datum/om/task/timed/handheld_experiment, user, target, duration = ((config_flags & EXPERIMENT_CONFIG_IMMEDIATE_ACTION) ? 0 : 1 SECOND), receiver = src, scanner = source)

/// Scanning the target for the selected experiment with a handheld handler (`scanner`).
/datum/om/task/timed/handheld_experiment
	complete_proc = /datum/experiment_handler/proc/run_handheld_experiment
	var/datum/scanner

/datum/experiment_handler/proc/run_handheld_experiment(datum/om/task/timed/handheld_experiment/task)
	var/datum/source = task.scanner
	var/atom/target = task.target
	var/mob/user = task.actor
	if(action_experiment(source, target, user))
		play_sfx(user, SFX_MACHINES_PING, 0.5)
		to_chat(user, span_notice("You scan [target]."))
	else if(!(config_flags & EXPERIMENT_CONFIG_SILENT_FAIL))
		play_sfx(user, SFX_MACHINES_BUZZ_SIGH, 0.5)
		to_chat(user, span_notice("[target] is not related to your currently selected experiment."))

/**
 * Hooks on destructive scans to try and run a destructive analyzer experiment.
 */
/datum/experiment_handler/proc/try_run_destructive_experiment(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/source = N.target
	var/datum/notice/machinery_destructive_scan/event = N
	var/atom/scan_target = event.scanned_atoms

	if(action_experiment(source, scan_target))
		play_sfx(source, SFX_MACHINES_PING, 0.5)
		source.atom_say("Destructive analysis complete.")

/**
 * Hooks on to RD server to try and run a spectral experiment.
 */
/datum/experiment_handler/proc/try_run_spectral_experiment(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/source = N.target
	var/atom/scan_target
	if(istype(N, /datum/notice/world_ghost_captured))
		var/datum/notice/world_ghost_captured/ghost_event = N
		scan_target = ghost_event.passing_entity
	else if(istype(N, /datum/notice/world_wight_captured))
		var/datum/notice/world_wight_captured/wight_event = N
		scan_target = wight_event.shadow_wight

	if(action_experiment(source, scan_target))
		play_sfx(source, SFX_MACHINES_PING, 0.5)
		source.atom_say("Spectral analysis complete.")

/**
 * Hooks on doppler array scans to try and run a explosive experiment.
 */
/datum/experiment_handler/proc/try_run_ordinance_experiment(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/source = N.target
	var/datum/notice/machinery_explosion_detected/event = N

	if(action_experiment(source, event.epicenter, event.devastation_range, event.heavy_impact_range, event.light_impact_range, event.seconds_taken))
		play_sfx(source, SFX_MACHINES_PING, 0.5)


/**
 * Announces a message to all experiment handlers
 *
 * Arguments:
 * * message - The message to announce
 */
/datum/experiment_handler/proc/announce_message_to_all(message)
	for(var/datum/experiment_handler/experi_handler as anything in REGISTRY_MEMBERS(REGISTRY_EXPERIMENT_HANDLERS))
		if(experi_handler.linked_web() != linked_web())
			continue
		experi_handler.owner?.atom_say(message)

/**
 * Announces a message to this experiment handler
 *
 * Arguments:
 * * message - The message to announce
 */
/datum/experiment_handler/proc/announce_message(message)
	owner?.atom_say(message)

/**
 * Attempts to perform the selected experiment given some arguments
 */
/datum/experiment_handler/proc/action_experiment(datum/source, ...)
	// Check if an experiment is selected
	if (selected_experiment() == null && !(config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE))
		return FALSE

	// Get arguments for passing to the experiment[s]
	var/list/arguments = list(src)
	arguments = args.len > 1 ? arguments + args.Copy(2) : arguments

	// Check if this handler is configured to be always active, in which case we
	// attempt to action every experiment that is available to this handler.
	if (config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE)
		var/any_success
		for (var/datum/experiment/experiment in linked_web().available_experiments)
			// Because this checks any experiment, we have to ensure it is allowable to be selected with can_select_experiment(...)
			// this handles the handler's blacklist, whitelist, etc (potentially refactor this in the future if possible because this could be expensive)
			if (can_select_experiment(experiment) && experiment.actionable(arglist(arguments)) && experiment.perform_experiment(arglist(arguments)))
				any_success = TRUE
		return any_success
	else
		// Returns true if the experiment was successfuly handled
		return selected_experiment().actionable(arglist(arguments)) && selected_experiment().perform_experiment(arglist(arguments))

/**
 * Hook for handling UI interaction via signals
 */
/datum/experiment_handler/proc/ui_handle_experiment(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/ui_act/event = N
	switch(event.action)
		if("open_experiments")
			configure_experiment(null, event.usr_)

/**
 * Attempts to show the user the experiment configuration panel
 *
 * Arguments:
 * * user - The user to show the experiment configuration panel to
 */
/datum/experiment_handler/proc/on_config_event(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = N.target
	var/mob/user
	if(istype(N, /datum/notice/attack_self))
		var/datum/notice/attack_self/self_event = N
		user = self_event.user
	else if(istype(N, /datum/notice/click_alt))
		var/datum/notice/click_alt/alt_event = N
		user = alt_event.mob
	configure_experiment(source, user)

/datum/experiment_handler/proc/configure_experiment(datum/source, mob/user)
	SHOULD_NOT_SLEEP(TRUE)
	INVOKE_ASYNC(src, PROC_REF(tgui_interact), user) // ALLOW(scheduler): tgui_interact may block on asset/window setup

/**
 * Attempts to show the user the experiment configuration panel
 *
 * Arguments:
 * * user - The user to show the experiment configuration panel to
 */
/datum/experiment_handler/proc/configure_experiment_click(datum/source, mob/user)
	SHOULD_NOT_SLEEP(TRUE)
	INVOKE_ASYNC(src, TYPE_PROC_REF(/datum, tgui_interact), user) // ALLOW(scheduler): tgui_interact may block on asset/window setup

/**
 * Attempts to link this experiment_handler to a provided techweb
 *
 * This proc attempts to link the handler to a provided techweb, overriding the existing techweb if relevant
 *
 * Arguments:
 * * new_web - The new techweb to link to
 */
/datum/experiment_handler/proc/link_techweb(datum/techweb/new_web)
	if (new_web == linked_web())
		return
	selected_experiment()?.on_unselected(src)
	rel_clear(src, nameof(selected_experiment))
	linked_web_static = new_web

/**
 * Unlinks this handler from the selected techweb
 */
/datum/experiment_handler/proc/unlink_techweb()
	selected_experiment()?.on_unselected(src)
	rel_clear(src, nameof(selected_experiment))
	linked_web_static = null

/**
 * Attempts to link this experiment_handler to a provided experiment
 *
 * Arguments:
 * * experiment - The experiment to attempt to link to
 */
/datum/experiment_handler/proc/link_experiment(datum/experiment/experiment)
	if (can_select_experiment(experiment))
		unlink_experiment()
		rel_set(src, nameof(selected_experiment), experiment)
		selected_experiment().on_selected(src)

/**
 * Unlinks this handler from the selected experiment
 */
/datum/experiment_handler/proc/unlink_experiment()
	selected_experiment()?.on_unselected(src)
	rel_clear(src, nameof(selected_experiment))

/**
 * Checks if an experiment is valid to be selected by this handler
 *
 * Arguments:
 * * experiment - The experiment to check
 */
/datum/experiment_handler/proc/can_select_experiment(datum/experiment/experiment)
	// Check that this experiments has no disallowed traits
	if (experiment.traits & disallowed_traits)
		return FALSE

	// Check against the list of allowed experimentors
	if (length(experiment.allowed_experimentors) && !is_type_in_list(owner, experiment.allowed_experimentors))
		return FALSE

	// Check that this experiment is visible currently
	if (!(experiment in linked_web()?.available_experiments))
		return FALSE

	// Check that this experiment type isn't blacklisted
	if(is_type_in_list(experiment, blacklisted_experiments))
		return FALSE

	// Finally, check against the allowed experiment types
	return is_type_in_list(experiment, allowed_experiments)

/datum/experiment_handler/ui_title(mob/user)
	var/atom/parent_atom = owner
	return "[parent_atom ? "[parent_atom.name] | " : ""]Experiment Configuration"

/datum/experiment_handler/tgui_static_data(mob/user)
	. = ..()
	var/atom/parent_atom = owner
	if(isrobot(parent_atom?.loc))
		var/mob/living/silicon/robot/owner_robot = parent_atom.loc
		.["theme"] = owner_robot.get_ui_theme()

/// /datum/experiment_handler's window data.
/datum/experiment_handler/ui_data(datum/act/eval/A)
	. = list(
		"always_active" = (config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE),
		"has_start_callback" = !isnull(start_experiment_spec),
	)
	.["techwebs"] = list()
	for (var/datum/techweb/techwebs as anything in SSresearch.techwebs)
		if(!length(techwebs.techweb_servers)) //no servers, we don't care
			if(techwebs == linked_web()) //disconnect if OUR techweb lost their servers.
				unlink_techweb()
			continue
		if(!length(SSresearch.find_valid_servers(get_turf(owner), techwebs)))
			continue
		var/list/data = list(
			web_id = techwebs.id,
			web_org = techwebs.organization,
			selected = (techwebs == linked_web()),
			ref = REF(techwebs),
			all_servers = (techwebs.techweb_servers || list()),
		)
		.["techwebs"] += list(data)
	.["experiments"] = list()
	if (linked_web())
		for (var/datum/experiment/experiment as anything in linked_web().available_experiments)
			if(!can_select_experiment(experiment))
				continue
			var/list/data = list(
				name = experiment.name,
				description = experiment.description,
				tag = experiment.exp_tag,
				selected = selected_experiment() == experiment,
				progress = experiment.check_progress(),
				performance_hint = experiment.performance_hint,
				ref = REF(experiment)
			)
			.["experiments"] += list(data)

/datum/experiment_handler/proc/ui_act_select_server(datum/act/op/A, ref)
	if(isnull(ref))
		return FALSE
	. = TRUE
	var/datum/techweb/new_techweb = ref
	if (new_techweb)
		link_techweb(new_techweb)
		return

/datum/experiment_handler/proc/ui_act_clear_server(datum/act/op/A)
	unlink_techweb()
	return OP_OK

/datum/experiment_handler/proc/ui_act_select_experiment(datum/act/op/A, ref)
	if(isnull(ref))
		return FALSE
	. = TRUE
	// Don't allow selection for always actives (no concept of active)
	if (config_flags & EXPERIMENT_CONFIG_ALWAYS_ACTIVE)
		return
	var/datum/experiment/experiment = ref
	if (experiment)
		link_experiment(experiment)

/datum/experiment_handler/proc/ui_act_clear_experiment(datum/act/op/A)
	unlink_experiment()
	return OP_OK

/datum/experiment_handler/proc/ui_act_start_experiment_callback(datum/act/op/A)
	om_run(start_experiment_spec, selected_experiment())


/// the selected_experiment this refers to (a relation view: null once it is deleted).
/datum/experiment_handler/proc/selected_experiment() as /datum/experiment
	return selected_experiment

/// A shared definition/flyweight (never cleared).
/datum/experiment_handler/proc/linked_web() as /datum/techweb
	return linked_web_static
