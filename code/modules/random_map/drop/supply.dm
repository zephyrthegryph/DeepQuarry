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
			var/obj/structure/largecrate/C = locate() in T
			for(var/drop_type in supplied_drop_types)
				var/atom/movable/A = new drop_type(T)
				if(!istype(A, /mob))
					if(!C) C = new(T)
					C.contents |= A
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
	var/mob/admin
	/// Categories still to offer: question = root type.
	var/list/categories = list(
		"Do you wish to add mobs?" = /mob/living,
		"Do you wish to add structures or machines?" = /obj,
		"Do you wish to add any non-weapon items?" = /obj/item,
		"Do you wish to add weapons?" = /obj/item,
		"Do you wish to add ABSOLUTELY ANYTHING ELSE? (you really shouldn't need to)" = /atom/movable,
	)
	var/current_root
	var/list/chosen_loot_types
	var/chosen_loot_type
	/// Orders being put together; prompts only hold handles, so this keeps them alive.
	var/static/list/open_orders = list()

/datum/supply_drop_order/New(mob/admin)
	src.admin = admin
	open_orders += src

/datum/supply_drop_order/Destroy()
	open_orders -= src
	admin = null
	return ..()

/datum/supply_drop_order/proc/ask(list/spec, on_answer, on_cancel)
	spec["requires"] = PROMPT_ADMIN(R_FUN)
	if(on_cancel)
		spec["on_cancel"] = on_cancel
	om_prompt(src, admin, spec, on_answer)

/datum/supply_drop_order/proc/start()
	ask(list("message" = "Do you wish to supply a custom loot list?", "title" = "Supply Drop", "choices" = list("No","Yes")), PROC_REF(custom_answered), PROC_REF(abandon))

/datum/supply_drop_order/proc/abandon(mob/user, datum/om/prompt/ask)
	qdel(src)

/datum/supply_drop_order/proc/custom_answered(mob/user, choice, datum/om/prompt/ask)
	if(choice == "Yes")
		chosen_loot_types = list()
		next_category()
		return
	ask(list("message" = "Do you wish to specify a loot type?", "title" = "Supply Drop", "choices" = list("No","Yes")), PROC_REF(specify_answered), PROC_REF(abandon))

/datum/supply_drop_order/proc/specify_answered(mob/user, choice, datum/om/prompt/ask)
	if(choice != "Yes")
		confirm()
		return
	ask(list("kind" = "list", "message" = "Select a loot type.", "title" = "Loot Selection", "choices" = GLOB.supply_drop), PROC_REF(loot_type_answered), PROC_REF(confirm_after_cancel))

/datum/supply_drop_order/proc/loot_type_answered(mob/user, loot_type, datum/om/prompt/ask)
	chosen_loot_type = loot_type
	confirm()

/datum/supply_drop_order/proc/confirm_after_cancel(mob/user, datum/om/prompt/ask)
	confirm()

/datum/supply_drop_order/proc/next_category()
	if(!length(categories))
		confirm()
		return
	var/question = categories[1]
	current_root = categories[question]
	categories.Cut(1, 2)
	ask(list("message" = question, "title" = "Supply Drop", "choices" = list("No","Yes")), PROC_REF(category_answered), PROC_REF(next_category_after_cancel))

/datum/supply_drop_order/proc/next_category_after_cancel(mob/user, datum/om/prompt/ask)
	next_category()

/datum/supply_drop_order/proc/category_answered(mob/user, choice, datum/om/prompt/ask)
	if(choice == "Yes")
		pick_loot()
	else
		next_category()

/datum/supply_drop_order/proc/pick_loot()
	var/list/choices = current_root == /atom/movable || current_root == /mob/living ? typesof(current_root) : subtypesof(current_root)
	ask(list("kind" = "list", "message" = "Select a new loot path. Cancel to finish.", "title" = "Loot Selection", "choices" = choices), PROC_REF(loot_picked), PROC_REF(next_category_after_cancel))

/datum/supply_drop_order/proc/loot_picked(mob/user, loot_path, datum/om/prompt/ask)
	if(!ispath(loot_path))
		next_category()
		return
	chosen_loot_types |= loot_path
	pick_loot()

/datum/supply_drop_order/proc/confirm()
	ask(list("message" = "Are you SURE you wish to deploy this supply drop? It will cause a sizable explosion and gib anyone underneath it.", "title" = "Supply Drop", "choices" = list("No","Yes")), PROC_REF(confirmed), PROC_REF(abandon))

/datum/supply_drop_order/proc/confirmed(mob/user, choice, datum/om/prompt/ask)
	if(choice == "Yes" && isturf(user.loc))
		log_admin("[key_name(user)] dropped supplies at ([user.x],[user.y],[user.z])")
		new /datum/random_map/droppod/supply(null, user.x-2, user.y-2, user.z, supplied_drops = chosen_loot_types, supplied_drop = chosen_loot_type)
	qdel(src)
