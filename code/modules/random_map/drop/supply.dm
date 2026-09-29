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
	/// The ordering admin's mob, as an om_handle() (read with admin()).
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
	rel_set(src, "admin", admin)
	open_orders += src

/// LC-refs: the ordering admin -- an OM handle, so it reads null once that mob is deleted.
/datum/supply_drop_order/proc/admin() as /mob
	return admin

/datum/supply_drop_order/lifecycle_dematerialize()
	..()
	open_orders -= src

/// Asks the admin a supply drop question. `on_cancel` runs on the order when the window is closed.
/datum/supply_drop_order/proc/ask(prompt_type, message, on_answer, on_cancel, list/choices)
	if(choices)
		om_ask(admin(), prompt_type, on_answer, order = src, cancel_proc = on_cancel, message = message, choices = choices)
	else
		om_ask(admin(), prompt_type, on_answer, order = src, cancel_proc = on_cancel, message = message)

/// A yes/no step of a supply drop order. Re-checked on the answer: the admin still has R_FUN.
/datum/om/prompt/confirm/supply_drop
	title = "Supply Drop"
	no_first = TRUE
	answer_on_no = TRUE
	requires = PROMPT_ADMIN(R_FUN)
	var/datum/supply_drop_order/order
	/// Runs on the order when the window is closed.
	var/cancel_proc

/datum/om/prompt/confirm/supply_drop/cancelled()
	if(order && cancel_proc)
		call(order, cancel_proc)()

/datum/om/prompt/confirm/supply_drop/refused(reason)
	qdel(order)

/// A list pick of a supply drop order. Re-checked on the answer: the admin still has R_FUN.
/datum/om/prompt/choice/supply_drop
	title = "Loot Selection"
	requires = PROMPT_ADMIN(R_FUN)
	var/datum/supply_drop_order/order
	/// Runs on the order when the window is closed.
	var/cancel_proc

/datum/om/prompt/choice/supply_drop/cancelled()
	if(order && cancel_proc)
		call(order, cancel_proc)()

/datum/om/prompt/choice/supply_drop/refused(reason)
	qdel(order)

/datum/supply_drop_order/proc/start()
	ask(/datum/om/prompt/confirm/supply_drop, "Do you wish to supply a custom loot list?", PROC_REF(custom_answered), PROC_REF(abandon))

/datum/supply_drop_order/proc/abandon()
	qdel(src)

/datum/supply_drop_order/proc/custom_answered(datum/om/prompt/confirm/supply_drop/answer)
	if(answer.yes)
		chosen_loot_types = list()
		next_category()
		return
	ask(/datum/om/prompt/confirm/supply_drop, "Do you wish to specify a loot type?", PROC_REF(specify_answered), PROC_REF(abandon))

/datum/supply_drop_order/proc/specify_answered(datum/om/prompt/confirm/supply_drop/answer)
	if(!answer.yes)
		confirm()
		return
	ask(/datum/om/prompt/choice/supply_drop, "Select a loot type.", PROC_REF(loot_type_answered), PROC_REF(confirm), GLOB.supply_drop)

/datum/supply_drop_order/proc/loot_type_answered(datum/om/prompt/choice/supply_drop/answer)
	chosen_loot_type = answer.choice
	confirm()

/datum/supply_drop_order/proc/next_category()
	if(categories_offered >= length(categories))
		confirm()
		return
	categories_offered++
	var/question = categories[categories_offered]
	current_root = categories[question]
	ask(/datum/om/prompt/confirm/supply_drop, question, PROC_REF(category_answered), PROC_REF(next_category))

/datum/supply_drop_order/proc/category_answered(datum/om/prompt/confirm/supply_drop/answer)
	if(answer.yes)
		pick_loot()
	else
		next_category()

/datum/supply_drop_order/proc/pick_loot()
	var/list/choices = current_root == /atom/movable || current_root == /mob/living ? typesof(current_root) : subtypesof(current_root)
	ask(/datum/om/prompt/choice/supply_drop, "Select a new loot path. Cancel to finish.", PROC_REF(loot_picked), PROC_REF(next_category), choices)

/datum/supply_drop_order/proc/loot_picked(datum/om/prompt/choice/supply_drop/answer)
	var/loot_path = answer.choice
	if(!ispath(loot_path))
		next_category()
		return
	chosen_loot_types |= loot_path
	pick_loot()

/datum/supply_drop_order/proc/confirm()
	ask(/datum/om/prompt/confirm/supply_drop, "Are you SURE you wish to deploy this supply drop? It will cause a sizable explosion and gib anyone underneath it.", PROC_REF(confirmed), PROC_REF(abandon))

/datum/supply_drop_order/proc/confirmed(datum/om/prompt/confirm/supply_drop/answer)
	var/mob/user = answer.answerer
	if(answer.yes && isturf(user.loc))
		log_admin("[key_name(user)] dropped supplies at ([user.x],[user.y],[user.z])")
		new /datum/random_map/droppod/supply(null, user.x-2, user.y-2, user.z, supplied_drops = chosen_loot_types, supplied_drop = chosen_loot_type)
	qdel(src)
