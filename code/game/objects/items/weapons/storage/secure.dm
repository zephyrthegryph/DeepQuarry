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
	var/emagged = 0
	var/open = 0
	w_class = ITEMSIZE_NORMAL
	max_storage_space = ITEMSIZE_SMALL * 7
	use_sound = SFX_ITEMS_STORAGE_BRIEFCASE
	special_handling = TRUE

TYPE_TABLE(/obj/item/storage/secure, hold_spec, list(HOLD_MAX_SIZE(ITEMSIZE_SMALL)))

/obj/item/storage/secure/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The service panel is [src.open ? "open" : "closed"]."

EXTEND_INTERACTIONS(/obj/item/storage/secure, \
	INTERACT_ITEM("Put in", PROC_REF(interaction_secure_item)), \
	INTERACT_ALT("Open", PROC_REF(interaction_secure_alt)), \
	INTERACT_USE("Keypad", PROC_REF(interaction_keypad)), \
)

/// Old attackby: locked, only an energy blade does anything; unlocked, the storage takes the item.
/obj/item/storage/secure/proc/interaction_secure_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(locked)
		if (istype(W, /obj/item/melee/energy/blade) && short_lock(user, "You slice through the lock of \the [src]"))
			fx_sparks(src.loc, 5, FALSE)
			play_sfx(src, SFX_WEAPONS_BLADE1)
			play_sfx(src, SFX_SPARKS)
			return INTERACTION_HANDLED_PASS

		//At this point you have exhausted all the special things to do when locked
		// ... but it's still locked.
		return INTERACTION_HANDLED_PASS

	// -> the storage's insertion
	return FALSE

/obj/item/storage/secure/screwdriver_act(mob/user, obj/item/tool)
	if(!locked)
		return ..()
	use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_SCREWDRIVER, volume = 0, receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, tool), claims = TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/item/storage/secure/proc/screwdriver_act_tool_done(mob/user, obj/item/tool)
	open = !open
	playsound(src, tool.usesound, 50, TRUE)
	user.show_message(span_notice("You [open ? "open" : "close"] the service panel."))

/obj/item/storage/secure/multitool_act(mob/user, obj/item/tool)
	if(!locked || !open || om_busy(src))
		return ..()
	user.show_message(span_notice("Now attempting to reset internal memory, please hold."), 1)
	om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(multitool_act_timed_done), done_args = list(user), claims = TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/item/storage/secure/proc/multitool_act_timed_done(mob/user)
	if(prob(40))
		l_setshort = TRUE
		l_set = FALSE
		code = ""
		user.show_message(span_notice("Internal memory reset. Please give it a few seconds to reinitialize."), 1)
		om_after(src, 8 SECONDS, PROC_REF(memory_reinitialized))
	else
		user.show_message(span_warning("Unable to reset internal memory."), 1)

/obj/item/storage/secure/MouseDrop(over_object, src_location, over_location)
	if (locked)
		src.add_fingerprint(usr)
		return
	..()

/// Old click_alt: opens only when unlocked; it never fell back to the default alt-click.
/obj/item/storage/secure/proc/interaction_secure_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if (isliving(user) && Adjacent(user) && (src.locked == 1))
		to_chat(user, span_warning("[src] is locked and cannot be opened!"))
	else if (isliving(user) && Adjacent(user) && (!src.locked))
		src.open(user)
	else
		for(var/mob/M in range(1))
			if (M.s_active == src)
				src.close(M)
	src.add_fingerprint(user)
	return TRUE

/// Old attack_self: after the storage's own self-use, the keypad.
/obj/item/storage/secure/proc/interaction_keypad(mob/user, obj/item/held, datum/interaction/interaction)
	if(interaction_self(user, held, interaction))
		return TRUE
	tgui_interact(user)
	return TRUE

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

/obj/item/storage/secure/proc/memory_reinitialized()
	l_setshort = FALSE

/obj/item/storage/secure/proc/emag_spark_done(mob/user, feedback)
	cut_overlays()
	add_overlay(icon_locking)
	locked = 0
	to_chat(user, (feedback ? feedback : "You short out the lock of \the [src]."))

DECLARE_EMAG(/obj/item/storage/secure, PROC_REF(on_emag), null)
/obj/item/storage/secure/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	return short_lock(user)

/// Shorts the lock out (an emag, or a blade slicing it). Returns 1 if it wasn't already.
/obj/item/storage/secure/proc/short_lock(mob/user, feedback)
	if(!emagged)
		emagged = 1
		src.add_overlay(icon_sparking)
		om_after(src, 6, PROC_REF(emag_spark_done), user, feedback)
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

TYPE_TABLE(/obj/item/storage/secure/briefcase, hold_spec, list(HOLD_MAX_SIZE(ITEMSIZE_NORMAL)))

EXTEND_INTERACTIONS(/obj/item/storage/secure/briefcase, INTERACT_HAND_UNGATED("Open", PROC_REF(interaction_briefcase_hand)))

/// Old attack_hand: a held briefcase opens only when unlocked; otherwise the storage's touch (pickup).
/obj/item/storage/secure/briefcase/proc/interaction_briefcase_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(src.loc != user)
		return FALSE
	if(src.locked == 1)
		to_chat(user, span_warning("[src] is locked and cannot be opened!"))
	else
		src.open(user)
	src.add_fingerprint(user)
	return TRUE

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

TYPE_TABLE(/obj/item/storage/secure/safe, hold_spec, list(HOLD_NOT(list(/obj/item/storage/secure/briefcase)), HOLD_MAX_SIZE(ITEMSIZE_LARGE)))

EXTEND_INTERACTIONS(/obj/item/storage/secure/safe, INTERACT_HAND_UNGATED("Keypad", TYPE_PROC_REF(/atom, interaction_open_ui)))

