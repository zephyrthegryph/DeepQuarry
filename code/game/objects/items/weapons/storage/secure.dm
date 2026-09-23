/*
 *	Absorbs /obj/item/secstorage.
 *	Reimplements it only slightly to use existing storage functionality.
 *
 *	Contains:
 *		Secure Briefcase
 *		Wall Safe
 */

// -----------------------------
//         Generic Item
// -----------------------------
/obj/item/storage/secure
	name = "secstorage"
	var/icon_locking = "secureb"
	var/icon_sparking = "securespark"
	var/icon_opened = "secure0"
	var/locked = 1
	var/code = ""
	var/l_code = null
	var/l_set = 0
	var/l_setshort = 0
	var/l_hacking = 0
	var/emagged = 0
	var/open = 0
	w_class = ITEMSIZE_NORMAL
	max_storage_space = ITEMSIZE_SMALL * 7
	use_sound = 'sound/items/storage/briefcase.ogg'
	special_handling = TRUE

/obj/item/storage/secure/hold_constraint()
	return list(HOLD_MAX_SIZE(ITEMSIZE_SMALL))

/obj/item/storage/secure/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The service panel is [src.open ? "open" : "closed"]."

/obj/item/storage/secure/attackby(obj/item/W as obj, mob/user as mob)
	if(locked)
		if (istype(W, /obj/item/melee/energy/blade) && emag_act(INFINITY, user, "You slice through the lock of \the [src]"))
			var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
			spark_system.set_up(5, 0, src.loc)
			spark_system.start()
			playsound(src, 'sound/weapons/blade1.ogg', 50, 1)
			playsound(src, "sparks", 50, 1)
			return

		//At this point you have exhausted all the special things to do when locked
		// ... but it's still locked.
		return

	// -> storage/attackby() what with handle insertion, etc
	..()

/obj/item/storage/secure/screwdriver_act(mob/user, obj/item/tool)
	if(!locked)
		return ..()
	if(use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_SCREWDRIVER, volume = 0))
		open = !open
		playsound(src, tool.usesound, 50, TRUE)
		user.show_message(span_notice("You [open ? "open" : "close"] the service panel."))
	return ITEM_INTERACT_SUCCESS

/obj/item/storage/secure/multitool_act(mob/user, obj/item/tool)
	if(!locked || !open || l_hacking)
		return ..()
	user.show_message(span_notice("Now attempting to reset internal memory, please hold."), 1)
	l_hacking = TRUE
	if(do_after(user, 10 SECONDS, target = src))
		if(prob(40))
			l_setshort = TRUE
			l_set = FALSE
			code = ""
			user.show_message(span_notice("Internal memory reset. Please give it a few seconds to reinitialize."), 1)
			sleep(8 SECONDS)
			l_setshort = FALSE
		else
			user.show_message(span_warning("Unable to reset internal memory."), 1)
	l_hacking = FALSE
	return ITEM_INTERACT_SUCCESS


/obj/item/storage/secure/MouseDrop(over_object, src_location, over_location)
	if (locked)
		src.add_fingerprint(usr)
		return
	..()

/obj/item/storage/secure/click_alt(mob/user as mob)
	if (isliving(user) && Adjacent(user) && (src.locked == 1))
		to_chat(user, span_warning("[src] is locked and cannot be opened!"))
	else if (isliving(user) && Adjacent(user) && (!src.locked))
		src.open(user)
	else
		for(var/mob/M in range(1))
			if (M.s_active == src)
				src.close(M)
	src.add_fingerprint(user)
	return

/obj/item/storage/secure/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	tgui_interact(user)

/obj/item/storage/secure/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SecureSafe", name)
		ui.open()

/obj/item/storage/secure/tgui_data(mob/user)
	var/list/data = list()
	data["locked"] = locked
	data["code"] = code
	data["emagged"] = emagged
	data["l_setshort"] = l_setshort
	data["l_set"] = l_set
	return data

/obj/item/storage/secure/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE
	switch (action)
		if("type")
			var/digit = params["digit"]
			if(digit == "E")
				if ((src.l_set == 0) && (length(src.code) == 5) && (!src.l_setshort) && (src.code != "ERROR"))
					src.l_code = src.code
					src.l_set = 1
				else if ((src.code == src.l_code) && (src.emagged == 0) && (src.l_set == 1))
					src.locked = 0
					cut_overlays()
					add_overlay(icon_opened)
					src.code = null
				else
					src.code = "ERROR"
			else
				if ((digit == "R") && (src.emagged == 0) && (!src.l_setshort))
					src.locked = 1
					cut_overlays()
					src.code = null
					src.close(ui.user)
				else
					src.code += text("[]", digit)
					if (length(src.code) > 5)
						src.code = "ERROR"
	src.add_fingerprint(ui.user)
	. = TRUE
	return

/obj/item/storage/secure/emag_act(remaining_charges, mob/user, feedback)
	if(!emagged)
		emagged = 1
		src.add_overlay(icon_sparking)
		sleep(6)
		cut_overlays()
		add_overlay(icon_locking)
		locked = 0
		to_chat(user, (feedback ? feedback : "You short out the lock of \the [src]."))
		return 1

// -----------------------------
//        Secure Briefcase
// -----------------------------
/obj/item/storage/secure/briefcase
	name = "secure briefcase"
	icon = 'icons/obj/storage.dmi'
	icon_state = "secure"
	item_state_slots = list(slot_r_hand_str = "case", slot_l_hand_str = "case")
	desc = "A large briefcase with a digital locking system."
	force = 8.0
	throw_speed = 1
	throw_range = 4
	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_NORMAL * 4

/obj/item/storage/secure/briefcase/hold_constraint()
	return list(HOLD_MAX_SIZE(ITEMSIZE_NORMAL))

/obj/item/storage/secure/briefcase/attack_hand(mob/user as mob)
	if ((src.loc == user) && (src.locked == 1))
		to_chat(user, span_warning("[src] is locked and cannot be opened!"))
	else if ((src.loc == user) && (!src.locked))
		src.open(user)
	else
		..()
		for(var/mob/M in range(1))
			if (M.s_active == src)
				src.close(M)
	src.add_fingerprint(user)
	return

// -----------------------------
//        Secure Safe
// -----------------------------

/obj/item/storage/secure/safe
	name = "secure safe"
	desc = "It doesn't seem all that secure. Oh well, it'll do."
	icon = 'icons/obj/storage.dmi'
	icon_state = "safe"
	layer = ABOVE_WINDOW_LAYER
	icon_opened = "safe0"
	icon_locking = "safeb"
	icon_sparking = "safespark"
	force = 8.0
	w_class = ITEMSIZE_NO_CONTAINER
	flags = WALL_ITEM
	anchored = TRUE
	density = FALSE
	starts_with = list(
		/obj/item/paper,
		/obj/item/pen
	)

/obj/item/storage/secure/safe/hold_constraint()
	var/list/refuses = list(/obj/item/storage/secure/briefcase)
	return list(HOLD_NOT(refuses), HOLD_MAX_SIZE(ITEMSIZE_LARGE))

/obj/item/storage/secure/safe/attack_hand(mob/user as mob)
	tgui_interact(user)
