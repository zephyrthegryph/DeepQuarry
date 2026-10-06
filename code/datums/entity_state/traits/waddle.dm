/datum/trait_state/waddle_trait

	var/waddling = 1
	var/waddle_z = 4
	var/waddle_min = -12
	var/waddle_max = 12
	var/waddle_time = 2

/datum/trait_state/waddle_trait/setup()
	if(!isliving(owner))
		return FALSE
	grant(owner, granted_verb(/mob/living/proc/waddle_adjust), src)
	return TRUE

/datum/trait_state/waddle_trait/attach()
	..()
	observe(owner, /datum/notice/moved, src, then(PROC_REF(handle_comp)))

/datum/trait_state/waddle_trait/proc/handle_comp(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if (QDELETED(our_atom()))
		return
	//Living owner only. No waddling while downed.
	if(living_owner())
		if(living_owner().stat != CONSCIOUS || living_owner().resting)
			return
	if(waddling)
		waddle_waddle(our_atom())

/// The owner loses the waddle verb.
/datum/trait_state/waddle_trait/detach()
	if(living_owner())
		revoke(living_owner(), granted_verb(/mob/living/proc/waddle_adjust), src)
	..()

/mob/living/verb/toggle_waddle()
	set name = "Toggle or Enable Waddling"
	set desc = "Allows you to toggle if you want to walk with a waddle or not!"
	set category = VERB_CAT_PREFERENCES_CHARACTER
	var/datum/trait_state/waddle_trait/comp = add_trait_state(/datum/trait_state/waddle_trait)
	if(comp)
		comp.waddling = !comp.waddling
		to_chat(src, span_warning("You will [ (comp.waddling) ? "now" : "no longer"] waddle."))

/mob/living/proc/waddle_debug() //Debug tool to debug waddling.
	set name = "WADDLE DEBUG"
	set desc = "Allows you to debug waddling!!"
	set category = VERB_CAT_PREFERENCES_CHARACTER
	return waddle_debug_stage(list())

/mob/living/proc/waddle_debug_stage(list/waddle_answers)
	var/datum/trait_state/waddle_trait/comp = get_trait_state(/datum/trait_state/waddle_trait)
	if(comp)
		var/Z = waddle_answers["a1"]
		if(isnull(Z))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a1", waddle_debugging = TRUE, question = "Desired Z.", title = "Set Z", default = 0.5, min_value = -INFINITY, max_value = INFINITY, fractional_window = TRUE)
			return
		comp.waddle_z = Z
		var/min = waddle_answers["a2"]
		if(isnull(min))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a2", waddle_debugging = TRUE, question = "Desired min.", title = "Set min", default = -4, min_value = -INFINITY, max_value = INFINITY, fractional_window = TRUE)
			return
		comp.waddle_min = min
		var/max = waddle_answers["a3"]
		if(isnull(max))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a3", waddle_debugging = TRUE, question = "Desired max.", title = "Set max", default = 4, min_value = 0, max_value = INFINITY, fractional_window = TRUE)
			return
		comp.waddle_max = max
		var/time = waddle_answers["a4"]
		if(isnull(time))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a4", waddle_debugging = TRUE, question = "Desired time.", title = "Set time", default = 2, min_value = 0, max_value = INFINITY, fractional_window = TRUE)
			return
		comp.waddle_time = time
		to_chat(src, "z = [Z] min = [min] max = [max] time = [time]")

/mob/living/proc/waddle_adjust()
	set name = "Waddle Adjust"
	set desc = "Allows you to adjust your waddling."
	set category = VERB_CAT_PREFERENCES_CHARACTER
	return waddle_adjust_stage(list())

/mob/living/proc/waddle_adjust_stage(list/waddle_answers)
	var/datum/trait_state/waddle_trait/comp = get_trait_state(/datum/trait_state/waddle_trait)
	if(comp)
		var/Z_height = waddle_answers["a5"]
		if(isnull(Z_height))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a5", waddle_debugging = FALSE, question = "Put the desired waddle height. (5 is default. 0 min 40 max)", title = "Set Height", default = 5, min_value = 0, max_value = 40, fractional_window = FALSE)
			return
		Z_height = Z_height/10 //Clear numbers
		if(Z_height > 4 || Z_height < 0 )
			to_chat(src, span_notice("Invalid height!"))
			return
		comp.waddle_z = Z_height

		var/min = waddle_answers["a6"]
		if(isnull(min))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a6", waddle_debugging = FALSE, question = "Put the desired waddle backwards lean. (4 is default. 0 min, 12 max)", title = "Set Back Lean", default = 4, min_value = 0, max_value = 12, fractional_window = FALSE)
			return
		if(min > 12 || min < 0 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_min = -min

		var/max = waddle_answers["a7"]
		if(isnull(max))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a7", waddle_debugging = FALSE, question = "Put the desired waddle forwards lean. (4 is default. 0 min, 12 max)", title = "Set Forwards Lean", default = 4, min_value = 0, max_value = 12, fractional_window = FALSE)
			return
		if(max > 12 || max < 0 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_max = max

		var/time = waddle_answers["a8"]
		if(isnull(time))
			open_request(src, /datum/prompt/number/waddle_settings, PROC_REF(waddle_settings_answered), answerer = src, waddle_answers = waddle_answers, answer_key = "a8", waddle_debugging = FALSE, question = "Put the desired waddle animation time. (20 is default. 10 min, 20 max)", title = "Set Time", default = 20, min_value = 10, max_value = 20, fractional_window = FALSE)
			return
		time = time/10 //Clear numbers
		if(time > 2 || time < 1 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_time = time
		to_chat(src, span_notice("You have set your waddle height to [comp.waddle_z*10], your back lean to [comp.waddle_min], your forward lean to [comp.waddle_max] and your waddle time to [comp.waddle_time*10]! You will now waddle!"))
		comp.waddling = 1 //Activate it!

/datum/trait_state/waddle_trait/proc/waddle_waddle(atom/movable/target)
	var/prev_pixel_z = our_atom().pixel_z

	animate(target, pixel_z = target.pixel_z + waddle_z, time = 0)
	var/prev_transform = target.transform //The person's default state.
	animate(pixel_z = prev_pixel_z, transform = turn(target.transform, pick(waddle_min, 0, waddle_max)), time=waddle_time)
	animate(transform = prev_transform, time = 0)

/// LC-refs: the waddling mob (our owner).
/datum/trait_state/waddle_trait/proc/our_atom() as /atom/movable
	return owner

/// LC-refs: our owner (always a living mob now).
/datum/trait_state/waddle_trait/proc/living_owner() as /mob/living
	return owner

/// Accepted answers remain cached while each step re-reads the current trait and repeats earlier writes.
/datum/prompt/number/waddle_settings
	timeout = 0
	var/list/waddle_answers
	var/answer_key
	var/waddle_debugging = FALSE
	var/fractional_window = FALSE

/datum/prompt/number/waddle_settings/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !fractional_window, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/mob/living/proc/waddle_settings_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = waddle_settings_apply(A)
	SStgui.update_uis(src)
	return .

/mob/living/proc/waddle_settings_apply(datum/act/request/A)
	var/datum/prompt/number/waddle_settings/ask = A.answer
	ask.waddle_answers[ask.answer_key] = ask.value
	if(ask.waddle_debugging)
		return waddle_debug_stage(ask.waddle_answers)
	return waddle_adjust_stage(ask.waddle_answers)
