/obj/structure/event_collector_blocker
	var/blocker_channel = "collector"
	var/base_icon = "blocker"

	icon = 'icons/obj/general_collector.dmi'
	icon_state = "blocker_on"
	desc = "blocker? I barely know er"

	anchored = TRUE
	density = TRUE
	unacidable = TRUE

	var/tools_to_fix = FALSE

	//how much we're currently blocking
	var/block_amount = 0

	//how much we'll block when broken
	var/default_block_amount = 100

	//tool to what's fucked up
	var/static/list/problem_descs = list(
		TOOL_CROWBAR = "a panel is dislodged.",
		TOOL_MULTITOOL = "a light next to a dataport is flashing some errors.",
		TOOL_SCREWDRIVER = "there's some loose screws inside.",
		TOOL_WIRECUTTER = "some loose wires are shorting things out.",
		TOOL_WRENCH = "One of the supporting bolts are concerningly loose.",
		TOOL_CABLE_COIL = "There's some wires that need replacement.",
		TOOL_WELDER = "One of the brackets has a cracked weld."
	)

	//tool to how we unfuck it
	var/static/list/fix_descs = list(
		TOOL_CROWBAR = "you lodge the panel back in place.",
		TOOL_MULTITOOL = "you reset the panel with the multitool.",
		TOOL_SCREWDRIVER = "you tighten the loose screws.",
		TOOL_WIRECUTTER = "you remove the excess wiring.",
		TOOL_WRENCH = "you tighten up the supporting bolts.",
		TOOL_CABLE_COIL = "you replace the worn wires.",
		TOOL_WELDER = "you fix up the worn weld."
	)

	//what tools we need
	var/list/active_repair_steps = list() // ALLOW(instance_list): d: event prop repair state
TRACKED(/obj/structure/event_collector_blocker, block_amount)

REGISTRY_MEMBERSHIP(/obj/structure/event_collector_blocker, REGISTRY_EVENT_COLLECTOR_BLOCKERS)

/// The look (the draw sweep: from its template).
/obj/structure/event_collector_blocker/draw(datum/look/look)
	..()
	look.state("[base_icon]_[block_amount ? "off" : "on"]")

/obj/structure/event_collector_blocker/proc/induce_failure(intensity = -1) //progress to remove from the machine
	if(intensity == -1)
		intensity = default_block_amount

	set_block_amount(intensity)
	if(tools_to_fix)
		active_repair_steps = list()
		for(var/i in 1 to 4)
			active_repair_steps += pick(list(TOOL_CROWBAR,TOOL_MULTITOOL,TOOL_SCREWDRIVER,TOOL_WRENCH,TOOL_CABLE_COIL,TOOL_WELDER)) //todo, make this a different list on the obj "Possible failures" or whatever.

/obj/structure/event_collector_blocker/proc/fix()
	set_block_amount(0)
	active_repair_steps = list()

/obj/structure/event_collector_blocker/examine(mob/user, infix, suffix)
	. = ..()
	if(block_amount)
		if(tools_to_fix)
			if(active_repair_steps.len >= 1)
				. += span_warning(problem_descs[active_repair_steps[active_repair_steps.len]])
			else
				. += span_warning("It looks kinda messed up!")
		else
			. += span_warning("Looks like the breaker flipped!")
	else
		. += span_notice("Looks like it's functioning normally")

/obj/structure/event_collector_blocker/proc/get_repair_message(mob/user)
	return "[user] repairs \the [src]!"

DECLARE_INTERACTIONS(/obj/structure/event_collector_blocker, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/structure/event_collector_blocker/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!tools_to_fix && block_amount > 0)
		user.visible_message(get_repair_message(user)) //swap this with a message var, or just change it to be suitable
		fix()
	return FALSE


/datum/task/timed/event_collector_blocker_repair_step
	duration = 2 SECONDS
	complete_proc = /obj/structure/event_collector_blocker/proc/repair_step_done
	var/obj/item/O
	var/step_count

/obj/structure/event_collector_blocker/proc/repair_step_done(datum/task/timed/event_collector_blocker_repair_step/task)
	var/obj/item/O = task.O
	var/mob/user = task.actor
	var/step_count = task.step_count
	if(active_repair_steps.len != step_count)
		return
	post_repair_handling(O,active_repair_steps[active_repair_steps.len],user)
	to_chat(user,span_notice(fix_descs[active_repair_steps[active_repair_steps.len]]))
	active_repair_steps.len = active_repair_steps.len - 1
	if(active_repair_steps.len == 0)
		fix()

/// Old attackby.
/obj/structure/event_collector_blocker/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(tools_to_fix)
		if(active_repair_steps.len >= 1)
			if(O.has_tool_quality(active_repair_steps[active_repair_steps.len]))
				if(!pre_repair_handling(O,active_repair_steps[active_repair_steps.len],user)) return INTERACTION_HANDLED_PASS
				task_start(/datum/task/timed/event_collector_blocker_repair_step, user, src, O = O, step_count = active_repair_steps.len)
			else
				to_chat(user,span_notice("this doesn't look like the right tool for the job..."))
	return INTERACTION_HANDLED_PASS

/obj/structure/event_collector_blocker/proc/pre_repair_handling(obj/item/O,toolType,mob/user) //can we use this tool?
	switch(toolType)
		if(TOOL_WELDER)
			var/obj/item/weldingtool/welder = O.get_welder()
			if(welder)
				if(welder.isOn())
					if(welder.get_fuel() > 5)
						return TRUE
					else
						to_chat(user,span_warning("There's not enough fuel to finish the repair!"))
				else
					to_chat(user,span_warning("It's hard to weld cold things! Turning the welder on might help!"))
			else
				return FALSE

		if(TOOL_CABLE_COIL)
			var/obj/item/stack/cable_coil/coil = O
			if(istype(coil))
				if(coil.can_use(5))
					return TRUE
				else
					to_chat(user,span_warning("There's not enough cable in the coil to fix this mess!"))
					return FALSE
	return TRUE

/obj/structure/event_collector_blocker/proc/post_repair_handling(obj/item/O,toolType,mob/user)
	switch(toolType) //snowflake code time
		if(TOOL_WELDER)
			var/obj/item/weldingtool/welder = O.get_welder()
			if(welder)
				welder.remove_fuel(5,user)
				playsound(src, welder.usesound, 50, 1)

		if(TOOL_CABLE_COIL)
			var/obj/item/stack/cable_coil/coil = O
			if(istype(coil))
				coil.use(5)

/obj/structure/event_collector_blocker/breaker //for these, if you change the base_icon you'll be good to go. ae, base_icon = breaker or circuit or whatever
	name = "Breaker"
	desc = "I barely know er!"

/obj/structure/event_collector_blocker/breaker/get_repair_message(mob/user)
	return "[user] flips \the [src] back on!"

/obj/structure/event_collector_blocker/circuit_panel
	name = "Circuit Panel"
	desc = "Looks complicated!"
	tools_to_fix = TRUE
