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
	EVENT_HANDLER
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
	var/datum/trait_state/waddle_trait/comp = get_trait_state(/datum/trait_state/waddle_trait)
	if(comp)
		var/Z = rerun_ask(src, "a1", PROC_REF(waddle_debug), args, /datum/om/prompt/number, message = "Desired Z.", title = "Set Z", default = 0.5, min = -INFINITY, round_entry = FALSE)
		if(isnull(Z))
			return
		comp.waddle_z = Z
		var/min = rerun_ask(src, "a2", PROC_REF(waddle_debug), args, /datum/om/prompt/number, message = "Desired min.", title = "Set min", default = -4, min = -INFINITY, round_entry = FALSE)
		if(isnull(min))
			return
		comp.waddle_min = min
		var/max = rerun_ask(src, "a3", PROC_REF(waddle_debug), args, /datum/om/prompt/number, message = "Desired max.", title = "Set max", default = 4, round_entry = FALSE)
		if(isnull(max))
			return
		comp.waddle_max = max
		var/time = rerun_ask(src, "a4", PROC_REF(waddle_debug), args, /datum/om/prompt/number, message = "Desired time.", title = "Set time", default = 2, round_entry = FALSE)
		if(isnull(time))
			return
		comp.waddle_time = time
		to_chat(src, "z = [Z] min = [min] max = [max] time = [time]")

/mob/living/proc/waddle_adjust()
	set name = "Waddle Adjust"
	set desc = "Allows you to adjust your waddling."
	set category = VERB_CAT_PREFERENCES_CHARACTER
	var/datum/trait_state/waddle_trait/comp = get_trait_state(/datum/trait_state/waddle_trait)
	if(comp)
		var/Z_height = rerun_ask(src, "a5", PROC_REF(waddle_adjust), args, /datum/om/prompt/number, message = "Put the desired waddle height. (5 is default. 0 min 40 max)", title = "Set Height", default = 5, max = 40)
		if(isnull(Z_height))
			return
		Z_height = Z_height/10 //Clear numbers
		if(Z_height > 4 || Z_height < 0 )
			to_chat(src, span_notice("Invalid height!"))
			return
		comp.waddle_z = Z_height

		var/min = rerun_ask(src, "a6", PROC_REF(waddle_adjust), args, /datum/om/prompt/number, message = "Put the desired waddle backwards lean. (4 is default. 0 min, 12 max)", title = "Set Back Lean", default = 4, max = 12)
		if(isnull(min))
			return
		if(min > 12 || min < 0 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_min = -min

		var/max = rerun_ask(src, "a7", PROC_REF(waddle_adjust), args, /datum/om/prompt/number, message = "Put the desired waddle forwards lean. (4 is default. 0 min, 12 max)", title = "Set Forwards Lean", default = 4, max = 12)
		if(isnull(max))
			return
		if(max > 12 || max < 0 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_max = max

		var/time = rerun_ask(src, "a8", PROC_REF(waddle_adjust), args, /datum/om/prompt/number, message = "Put the desired waddle animation time. (20 is default. 10 min, 20 max)", title = "Set Time", default = 20, max = 20, min = 10)
		if(isnull(time))
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
