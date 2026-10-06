/datum/random_map/droppod/supply
	descriptor = "supply drop"
	limit_x = 5
	limit_y = 5

	placement_explosion_light = 7
	placement_explosion_flash = 5

// UNLIKE THE DROP POD, this map deals ENTIRELY with strings and types.
// Drop type is a string representing a mode rather than an atom or path.
// supplied_drop_types is a list of types to spawn in the pod.
/datum/random_map/droppod/supply/get_spawned_drop(turf/T)

	if(!drop_type) drop_type = pick(GLOB.supply_drop)

	if(drop_type == "custom")
		if(length(supplied_drop_types))
			var/obj/structure/largecrate/C = locate_on(T, /obj/structure/largecrate)
			for(var/drop_type in supplied_drop_types)
				var/atom/movable/A = new drop_type(T)
				if(!istype(A, /mob))
					if(!C) C = new(T)
					A.forceMove(C)
			return
		else
			drop_type = pick(GLOB.supply_drop)

	if(istype(drop_type, /datum/supply_drop_loot))
		var/datum/supply_drop_loot/SDL = drop_type
		SDL.drop(T)
	else
		log_world("## ERROR Unhandled drop type: [drop_type]")

ADMIN_VERB(call_supply_drop, R_FUN, "Call Supply Drop", "Call an immediate supply drop on your location.", ADMIN_CATEGORY_FUN_DROP_POD)
	var/datum/supply_drop_order/order = new(user.mob)
	order.start()

/// An admin putting together a supply drop: the custom loot list is picked one type at a time
/// per category (cancel ends a category), then the drop is confirmed and lands on the admin.
/datum/supply_drop_order
	/// Relation view: the ordering admin's mob (read with admin()).
	var/tmp/mob/admin
	/// The categories offered in order: question = root type. Shared by every order.
	var/static/list/categories = list(
		"Do you wish to add mobs?" = /mob/living,
		"Do you wish to add structures or machines?" = /obj,
		"Do you wish to add any non-weapon items?" = /obj/item,
		"Do you wish to add weapons?" = /obj/item,
		"Do you wish to add ABSOLUTELY ANYTHING ELSE? (you really shouldn't need to)" = /atom/movable,
	)
	/// How many of `categories` have been offered so far.
	var/categories_offered = 0
	var/current_root
	var/list/chosen_loot_types
	var/chosen_loot_type
	/// Orders being put together; prompts only hold handles, so this keeps them alive.
	var/static/list/open_orders = list()

/datum/supply_drop_order/New(mob/admin)
	rel_set(src, nameof(admin), admin)
	rel_add(src, nameof(open_orders), src)

/// The ordering admin (null once that mob is deleted).
/datum/supply_drop_order/proc/admin() as /mob
	return admin

/datum/supply_drop_order/lifecycle_dematerialize()
	..()
	rel_remove(src, nameof(open_orders), src)

/// Asks the admin a supply drop question; an explicit close runs its stage's cancellation action.
/datum/supply_drop_order/proc/ask(prompt_type, message, on_answer, on_cancel, list/choices)
	var/mob/user = admin()
	if(!ismob(user) || QDELETED(user))
		return
	if(choices)
		open_request(src, prompt_type, PROC_REF(answered), answerer = user, answer_callback = on_answer, cancel_callback = on_cancel, question = message, choices = choices)
	else
		open_request(src, prompt_type, PROC_REF(answered), answerer = user, answer_callback = on_answer, cancel_callback = on_cancel, question = message)

/// All stages preserve the original R_FUN answer check and unlimited timeout.
/datum/prompt/choice/supply_drop
	title = "Loot Selection"
	rights = R_FUN
	timeout = 0
	var/answer_callback
	var/cancel_callback

/datum/prompt/choice/supply_drop/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"

/datum/prompt/choice/supply_drop/confirm
	title = "Supply Drop"
	choices = list("No", "Yes")
	buttons = TRUE

/datum/supply_drop_order/proc/answered(datum/act/request/A)
	var/datum/prompt/choice/supply_drop/answer = A.request
	if(QDELETED(admin()))
		return
	if(A.answer)
		var/datum/result/result = safe_call(answer.answer_callback, A)
		if(!result.ok)
			stack_trace("supply drop answer [answer.answer_callback]: [result.error]")
		return result.value
	if(answer.outcome == REQ_CANCELLED && isnull(answer.value))
		if(answer.cancel_callback)
			var/datum/result/result = safe_call(answer.cancel_callback)
			if(!result.ok)
				stack_trace("supply drop close [answer.cancel_callback]: [result.error]")
			return result.value
		return
	abandon()

/datum/supply_drop_order/proc/start()
	ask(/datum/prompt/choice/supply_drop/confirm, "Do you wish to supply a custom loot list?", PROC_REF(custom_answered), PROC_REF(abandon))

/datum/supply_drop_order/proc/abandon()
	spent(src)

/datum/supply_drop_order/proc/custom_answered(datum/act/request/A)
	if((A.answer.value == "Yes"))
		chosen_loot_types = list()
		next_category()
		return
	ask(/datum/prompt/choice/supply_drop/confirm, "Do you wish to specify a loot type?", PROC_REF(specify_answered), PROC_REF(abandon))

/datum/supply_drop_order/proc/specify_answered(datum/act/request/A)
	if(!(A.answer.value == "Yes"))
		confirm()
		return
	ask(/datum/prompt/choice/supply_drop, "Select a loot type.", PROC_REF(loot_type_answered), PROC_REF(confirm), GLOB.supply_drop)

/datum/supply_drop_order/proc/loot_type_answered(datum/act/request/A)
	chosen_loot_type = A.answer.value
	confirm()

/datum/supply_drop_order/proc/next_category()
	if(categories_offered >= length(categories))
		confirm()
		return
	categories_offered++
	var/question = categories[categories_offered]
	current_root = categories[question]
	ask(/datum/prompt/choice/supply_drop/confirm, question, PROC_REF(category_answered), PROC_REF(next_category))

/datum/supply_drop_order/proc/category_answered(datum/act/request/A)
	if((A.answer.value == "Yes"))
		pick_loot()
	else
		next_category()

/datum/supply_drop_order/proc/pick_loot()
	var/list/choices = current_root == /atom/movable || current_root == /mob/living ? typesof(current_root) : subtypesof(current_root)
	ask(/datum/prompt/choice/supply_drop, "Select a new loot path. Cancel to finish.", PROC_REF(loot_picked), PROC_REF(next_category), choices)

/datum/supply_drop_order/proc/loot_picked(datum/act/request/A)
	var/loot_path = A.answer.value
	if(!ispath(loot_path))
		next_category()
		return
	chosen_loot_types |= loot_path
	pick_loot()

/datum/supply_drop_order/proc/confirm()
	ask(/datum/prompt/choice/supply_drop/confirm, "Are you SURE you wish to deploy this supply drop? It will cause a sizable explosion and gib anyone underneath it.", PROC_REF(confirmed), PROC_REF(abandon))

/datum/supply_drop_order/proc/confirmed(datum/act/request/A)
	var/mob/user = A.request.answerer
	if((A.answer.value == "Yes") && isturf(user.loc))
		log_admin("[key_name(user)] dropped supplies at ([user.x],[user.y],[user.z])")
		new /datum/random_map/droppod/supply(null, user.x-2, user.y-2, user.z, supplied_drops = chosen_loot_types, supplied_drop = chosen_loot_type)
	spent(src)
