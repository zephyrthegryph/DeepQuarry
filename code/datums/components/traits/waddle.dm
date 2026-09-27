/datum/component/waddle_trait
	var/atom/movable/our_atom
	var/mob/living/living_owner

	var/waddling = 1
	var/waddle_z = 4
	var/waddle_min = -12
	var/waddle_max = 12
	var/waddle_time = 2

/datum/component/waddle_trait/Initialize()
	if (!isobj(parent) && !ismob(parent))
		return COMPONENT_INCOMPATIBLE
	if(isliving(parent))
		living_owner = parent
		add_verb(living_owner, /mob/living/proc/waddle_adjust)
		//add_verb(living_owner, /mob/living/proc/waddle_debug)
	our_atom = parent
	RegisterSignal(our_atom, COMSIG_MOVABLE_MOVED, PROC_REF(handle_comp))

/datum/component/waddle_trait/proc/handle_comp()
	SIGNAL_HANDLER
	if (QDELETED(our_atom))
		return
	//Living owner only. No waddling while downed.
	if(living_owner)
		if(living_owner.stat != CONSCIOUS || living_owner.resting)
			return
	if(waddling)
		waddle_waddle(our_atom)

/datum/component/waddle_trait/Destroy(force = FALSE)
	UnregisterSignal(our_atom, COMSIG_MOVABLE_MOVED)
	if(living_owner)
		remove_verb(living_owner, /mob/living/proc/waddle_adjust)
		//remove_verb(living_owner, /mob/living/proc/waddle_debug)
	living_owner = null
	our_atom = null
	. = ..()

/mob/living/verb/toggle_waddle()
	set name = "Toggle or Enable Waddling"
	set desc = "Allows you to toggle if you want to walk with a waddle or not!"
	set category = "Preferences.Character"
	var/datum/component/waddle_trait/comp = LoadComponent(/datum/component/waddle_trait)
	if(comp)
		comp.waddling = !comp.waddling
		to_chat(src, span_warning("You will [ (comp.waddling) ? "now" : "no longer"] waddle."))

/mob/living/proc/waddle_debug() //Debug tool to debug waddling.
	set name = "WADDLE DEBUG"
	set desc = "Allows you to debug waddling!!"
	set category = "Preferences.Character"
	var/datum/component/waddle_trait/comp = GetComponent(/datum/component/waddle_trait)
	if(comp)
		var/Z = rerun_prompt(src, "a1", list("kind" = "number", "message" = "Desired Z.", "title" = "Set Z", "default" = 0.5, "min" = -INFINITY, "round" = FALSE), PROC_REF(waddle_debug), args)
		if(isnull(Z))
			return
		comp.waddle_z = Z
		var/min = rerun_prompt(src, "a2", list("kind" = "number", "message" = "Desired min.", "title" = "Set min", "default" = -4, "min" = -INFINITY, "round" = FALSE), PROC_REF(waddle_debug), args)
		if(isnull(min))
			return
		comp.waddle_min = min
		var/max = rerun_prompt(src, "a3", list("kind" = "number", "message" = "Desired max.", "title" = "Set max", "default" = 4, "round" = FALSE), PROC_REF(waddle_debug), args)
		if(isnull(max))
			return
		comp.waddle_max = max
		var/time = rerun_prompt(src, "a4", list("kind" = "number", "message" = "Desired time.", "title" = "Set time", "default" = 2, "round" = FALSE), PROC_REF(waddle_debug), args)
		if(isnull(time))
			return
		comp.waddle_time = time
		to_chat(src, "z = [Z] min = [min] max = [max] time = [time]")

/mob/living/proc/waddle_adjust()
	set name = "Waddle Adjust"
	set desc = "Allows you to adjust your waddling."
	set category = "Preferences.Character"
	var/datum/component/waddle_trait/comp = GetComponent(/datum/component/waddle_trait)
	if(comp)
		var/Z_height = rerun_prompt(src, "a5", list("kind" = "number", "message" = "Put the desired waddle height. (5 is default. 0 min 40 max)", "title" = "Set Height", "default" = 5, "max" = 40, "min" = 0), PROC_REF(waddle_adjust), args)
		if(isnull(Z_height))
			return
		Z_height = Z_height/10 //Clear numbers
		if(Z_height > 4 || Z_height < 0 )
			to_chat(src, span_notice("Invalid height!"))
			return
		comp.waddle_z = Z_height

		var/min = rerun_prompt(src, "a6", list("kind" = "number", "message" = "Put the desired waddle backwards lean. (4 is default. 0 min, 12 max)", "title" = "Set Back Lean", "default" = 4, "max" = 12, "min" = 0), PROC_REF(waddle_adjust), args)
		if(isnull(min))
			return
		if(min > 12 || min < 0 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_min = -min

		var/max = rerun_prompt(src, "a7", list("kind" = "number", "message" = "Put the desired waddle forwards lean. (4 is default. 0 min, 12 max)", "title" = "Set Forwards Lean", "default" = 4, "max" = 12, "min" = 0), PROC_REF(waddle_adjust), args)
		if(isnull(max))
			return
		if(max > 12 || max < 0 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_max = max

		var/time = rerun_prompt(src, "a8", list("kind" = "number", "message" = "Put the desired waddle animation time. (20 is default. 10 min, 20 max)", "title" = "Set Time", "default" = 20, "max" = 20, "min" = 10), PROC_REF(waddle_adjust), args)
		if(isnull(time))
			return
		time = time/10 //Clear numbers
		if(time > 2 || time < 1 )
			to_chat(src, span_notice("Invalid number!"))
			return
		comp.waddle_time = time
		to_chat(src, span_notice("You have set your waddle height to [comp.waddle_z*10], your back lean to [comp.waddle_min], your forward lean to [comp.waddle_max] and your waddle time to [comp.waddle_time*10]! You will now waddle!"))
		comp.waddling = 1 //Activate it!

/datum/component/waddle_trait/proc/waddle_waddle(atom/movable/target)
	var/prev_pixel_z = our_atom.pixel_z

	animate(target, pixel_z = target.pixel_z + waddle_z, time = 0)
	var/prev_transform = target.transform //The person's default state.
	animate(pixel_z = prev_pixel_z, transform = turn(target.transform, pick(waddle_min, 0, waddle_max)), time=waddle_time)
	animate(transform = prev_transform, time = 0)
