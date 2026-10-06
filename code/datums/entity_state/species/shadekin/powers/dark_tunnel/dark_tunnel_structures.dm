REGISTRY_MEMBERSHIP(/obj/structure/dark_portal/hub, REGISTRY_DARKPORTAL_HUBS)
REGISTRY_MEMBERSHIP(/obj/structure/dark_portal/minion, REGISTRY_DARKPORTAL_MINIONS)
/obj/structure/dark_portal
	name = "Dark portal"
	icon = 'icons/obj/shadekin_portal.dmi'
	density = TRUE
	anchored = TRUE
	var/locked = null
	var/locked_name = ""
	var/one_time_use = FALSE
	var/precision = 1

/obj/structure/dark_portal/proc/close_portal()
	return

/obj/structure/dark_portal/proc/teleport(atom/movable/M as mob|obj)
	if(!locked)
		return
	if(isliving(M))
		var/mob/living/to_check = M
		var/datum/shadekin/SK = to_check.shadekin
		if(SK && SK.in_dark_respite)
			to_chat(M, span_warning("You can't go through this portal so soon after an emergency warp!"))
			to_check.status_at_least(STAT_STUNNED, 10)
			return

	do_teleport(M, locked, precision, channel = TELEPORT_CHANNEL_QUANTUM)

	if(one_time_use)
		one_time_use = 0
		close_portal()
	return

// These things are always on. By default they always teleport you to themselves.
/obj/structure/dark_portal/hub
	icon_state = "hub_portal"
	desc = "A large portal. Touching it without going through may alter the destination."
	var/list/destination_station_areas // Override this in map files!
	var/list/destination_wilderness_areas // Override this in map files!

/obj/structure/dark_portal/hub/Initialize(mapload)
	. = ..()
	locked = src
	locked_name = src.name
	set_light(2, 3, "#ffffff")

/obj/structure/dark_portal/hub/close_portal()
	locked = src
	locked_name = src.name
	precision = 1

DECLARE_INTERACTIONS(/obj/structure/dark_portal/hub, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/dark_portal/hub/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	return portal_hand_stage(user, held, interaction, list())

/obj/structure/dark_portal/hub/proc/portal_hand_stage(mob/living/user, obj/item/held, datum/interaction/interaction, list/answers)
	if(!isliving(user))
		return TRUE
	var/datum/shadekin/SK = user.get_shadekin_state()
	if(SK)
		if(SK.in_dark_respite)
			to_chat(user, span_warning("You can't use this so soon after an emergency warp!"))
			return TRUE
		if(SK.in_phase)
			to_chat(user, span_warning("You can't use this while phase shifted!"))
			return TRUE
		if(locked != src)
			if(!("a1" in answers))
				open_request(src, /datum/prompt/choice/dark_portal_review, PROC_REF(portal_hand_answered), answerer = user, operator = user, held_item = held, interaction_context = interaction, answers = answers, answer_key = "a1", buttons = TRUE, question = "This portal is currently open to [locked_name]. Change the portal destination?", title = "Change Portal Destination", choices = list("Yes", "Cancel"))
				return TRUE
			var/confirm = answers["a1"]
			if(isnull(confirm))
				return TRUE
			if(!confirm || confirm == "Cancel")
				return TRUE
		var/list/L = list()
		for(var/obj/structure/dark_portal/hub/H in REGISTRY_MEMBERS(REGISTRY_DARKPORTAL_HUBS))
			if(H == src)
				L["This Portal"] = H
			else
				L[H.name] = H
		for(var/obj/structure/dark_portal/minion/M in REGISTRY_MEMBERS(REGISTRY_DARKPORTAL_MINIONS))
			var/tmpname = "Dark Portal ([get_area(M)])"
			L[tmpname] = M
		if(!("a2" in answers))
			open_request(src, /datum/prompt/choice/dark_portal_review, PROC_REF(portal_hand_answered), answerer = user, operator = user, held_item = held, interaction_context = interaction, answers = answers, answer_key = "a2", buttons = FALSE, question = "Please select a hub portal to connect to.", title = "Portal Menu", choices = L)
			return TRUE
		var/desc = answers["a2"]
		if(isnull(desc))
			return TRUE
		if(!desc)
			return TRUE
		locked = L[desc]
		locked_name = desc
		return TRUE
	else if(locked_name == "somewhere on the station" || locked_name == "somewhere in the wilderness")
		to_chat(user, span_warning("The portal distorts for a moment, before returning to how it was, seemingly already determined where to send you."))
		return TRUE
	else if(istype(user, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = user
		if(H.job && H.job != JOB_OUTSIDER && LAZYLEN(destination_station_areas))
			var/list/floors = list()
			var/area/picked_area = pick(destination_station_areas)
			for(var/turf/simulated/floor/floor in get_area_turfs(picked_area))
				floors.Add(floor)
			if(!LAZYLEN(floors))
				log_and_message_admins("[src]: There were no floors to teleport to in [picked_area]!")
				to_chat(user, span_warning("The portal distorts for a moment, seemingly unable to determine where to send you."))
				close_portal()
				destination_station_areas.Remove(picked_area)
				return TRUE
			locked = pick(floors)
			locked_name = "somewhere on the station"
			one_time_use = TRUE
			precision = 0
			to_chat(user, span_notice("The portal distorts for a moment, resolving itself soon after. You feel like it will lead you to the station now."))
			return TRUE
	if(!LAZYLEN(destination_wilderness_areas))
		to_chat(user, span_warning("The portal distorts for a moment, seemingly unable to determine where to send you."))
		close_portal()
		return TRUE
	var/list/floors = list()
	var/area/picked_area = pick(destination_wilderness_areas)
	for(var/turf/simulated/floor/floor in get_area_turfs(picked_area))
		floors.Add(floor)
	if(!LAZYLEN(floors))
		log_and_message_admins("[src]: There were no floors to teleport to in [picked_area]!")
		to_chat(user, span_warning("The portal distorts for a moment, seemingly unable to determine where to send you."))
		close_portal()
		destination_wilderness_areas.Remove(picked_area)
		return TRUE
	locked = pick(floors)
	locked_name = "somewhere in the wilderness"
	one_time_use = TRUE
	precision = 0
	to_chat(user, span_notice("The portal distorts for a moment, resolving itself soon after. You feel like it will lead you to somewhere in the wilderness now."))
	return TRUE

CAPABILITIES(/obj/structure/dark_portal/hub)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

CAPABILITIES(/obj/structure/dark_portal/minion)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

/// Something walked into it (the bump action's notice).
/obj/structure/dark_portal/hub/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/M = N.bumper
	teleport(M)
	return

// These things have an off state. A shadekin has to boop them to turn it on
/obj/structure/dark_portal/minion
	icon_state = "minion0"

/obj/structure/dark_portal/minion/close_portal()
	locked = null
	locked_name = ""
	precision = 1
	icon_state = "minion0"

DECLARE_INTERACTIONS(/obj/structure/dark_portal/minion, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/dark_portal/minion/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	return portal_hand_stage(user, held, interaction, list())

/obj/structure/dark_portal/minion/proc/portal_hand_stage(mob/living/user, obj/item/held, datum/interaction/interaction, list/answers)
	if(!isliving(user))
		return TRUE
	var/datum/shadekin/SK = user.get_shadekin_state()
	if(SK)
		if(SK.in_dark_respite)
			to_chat(user, span_warning("You can't use this so soon after an emergency warp!"))
			return TRUE
		if(SK.in_phase)
			to_chat(user, span_warning("You can't use this while phase shifted!"))
			return TRUE
		if(icon_state == "minion1")
			if(!("a3" in answers))
				open_request(src, /datum/prompt/choice/dark_portal_review, PROC_REF(portal_hand_answered), answerer = user, operator = user, held_item = held, interaction_context = interaction, answers = answers, answer_key = "a3", buttons = TRUE, question = "This portal is currently open to [locked_name]. Close this portal to the dark?", title = "Close Portal", choices = list("Yes", "Cancel"))
				return TRUE
			var/confirm = answers["a3"]
			if(isnull(confirm))
				return TRUE
			if(!confirm || confirm == "Cancel")
				return TRUE
			if(confirm == "Yes")
				close_portal()
				return TRUE
		if(SK.shadekin_get_energy() < 10)
			to_chat(user, span_warning("Not enough energy to open up the portal! (10 required)"))
			return TRUE
		if(!LAZYLEN(REGISTRY_MEMBERS(REGISTRY_DARKPORTAL_HUBS)))
			to_chat(user, span_warning("No hub portals exist!"))
			return TRUE
		if(LAZYLEN(REGISTRY_MEMBERS(REGISTRY_DARKPORTAL_HUBS)) == 1)
			SK.shadekin_adjust_energy(-10)
			var/obj/structure/dark_portal/target = REGISTRY_MEMBERS(REGISTRY_DARKPORTAL_HUBS)[1]
			locked = target
			locked_name = target.name
			icon_state = "minion1"
			after(src, 5 MINUTES, PROC_REF(check_to_close), with = list(target))
			return TRUE
		var/list/L = list()
		for(var/obj/structure/dark_portal/hub/H in REGISTRY_MEMBERS(REGISTRY_DARKPORTAL_HUBS))
			L[H.name] = H
		if(!("a4" in answers))
			open_request(src, /datum/prompt/choice/dark_portal_review, PROC_REF(portal_hand_answered), answerer = user, operator = user, held_item = held, interaction_context = interaction, answers = answers, answer_key = "a4", buttons = FALSE, question = "Please select a hub portal to connect to.", title = "Portal Menu", choices = L)
			return TRUE
		var/desc = answers["a4"]
		if(isnull(desc))
			return TRUE
		if(!desc)
			return TRUE
		locked = L[desc]
		locked_name = desc
		icon_state = "minion1"
		after(src, 5 MINUTES, PROC_REF(check_to_close_desc), with = list(locked))
		return TRUE
	else if(!istype(user, /mob/living))
		return TRUE
	else if(icon_state == "minion0")
		to_chat(user, span_notice("You touch the portal... nothing happens."))
	else
		to_chat(user, span_notice("You touch the portal, your hand able to pass through without harm."))
	return TRUE

/obj/structure/dark_portal/proc/check_to_close(obj/structure/dark_portal/target)
	if(locked == target)
		close_portal()

/obj/structure/dark_portal/proc/check_to_close_desc(old_locked)
	if(locked == old_locked)
		close_portal()

/// Something walked into it (the bump action's notice).
/obj/structure/dark_portal/minion/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/M = N.bumper
	if(icon_state == "minion1")
		teleport(M)
	return

/obj/structure/dark_portal/hub/proc/portal_hand_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = portal_hand_apply(A)
	SStgui.update_uis(src)

/obj/structure/dark_portal/hub/proc/portal_hand_apply(datum/act/request/A)
	var/datum/prompt/choice/dark_portal_review/ask = A.answer
	ask.answers[ask.answer_key] = ask.value
	return portal_hand_stage(ask.operator, ask.held_item, ask.interaction_context, ask.answers)

/obj/structure/dark_portal/minion/proc/portal_hand_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = portal_hand_apply(A)
	SStgui.update_uis(src)

/obj/structure/dark_portal/minion/proc/portal_hand_apply(datum/act/request/A)
	var/datum/prompt/choice/dark_portal_review/ask = A.answer
	ask.answers[ask.answer_key] = ask.value
	return portal_hand_stage(ask.operator, ask.held_item, ask.interaction_context, ask.answers)

/datum/prompt/choice/dark_portal_review
	timeout = 0
	var/mob/living/operator
	var/obj/item/held_item
	var/datum/interaction/interaction_context
	var/operator_expected = FALSE
	var/held_item_expected = FALSE
	var/interaction_context_expected = FALSE
	var/list/answers
	var/answer_key

CAPABILITIES(/datum/prompt/choice/dark_portal_review)
	ref_one(nameof(operator), /mob/living)
	ref_one(nameof(held_item), /obj/item)
	ref_one(nameof(interaction_context), /datum/interaction)

/datum/prompt/choice/dark_portal_review/prepare(datum/act/A)
	. = ..()
	var/mob/living/captured_operator = operator
	var/obj/item/captured_held = held_item
	var/datum/interaction/captured_interaction = interaction_context
	operator_expected = !isnull(captured_operator)
	held_item_expected = !isnull(captured_held)
	interaction_context_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(operator))
	rel_clear(src, nameof(held_item))
	rel_clear(src, nameof(interaction_context))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(operator), captured_operator)
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(held_item), captured_held)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(interaction_context), captured_interaction)

/datum/prompt/choice/dark_portal_review/recheck_extra()
	if((operator_expected && QDELETED(operator)) || (held_item_expected && QDELETED(held_item)) || (interaction_context_expected && QDELETED(interaction_context)))
		return "gone"
