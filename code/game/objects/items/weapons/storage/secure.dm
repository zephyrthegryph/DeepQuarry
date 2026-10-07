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
	/// The lock is being shorted out: the sparks show until it gives.
	var/sparking = FALSE
	w_class = ITEMSIZE_NORMAL
	max_storage_space = ITEMSIZE_SMALL * 7
	use_sound = SFX_ITEMS_STORAGE_BRIEFCASE
	special_handling = TRUE

TRACKED(/obj/item/storage/secure, locked)
TRACKED(/obj/item/storage/secure, code)
TRACKED(/obj/item/storage/secure, l_set)
TRACKED(/obj/item/storage/secure, l_setshort)
TRACKED(/obj/item/storage/secure, emagged)
TRACKED(/obj/item/storage/secure, open)
TRACKED(/obj/item/storage/secure, sparking)

MSG_DEF_SELF(secure/locked, "It is locked and cannot be opened!")

// The keypad lock. While it is locked the safe takes nothing and does not open: only an energy blade does anything (it shorts the lock out), and so
// does an emag. A screwdriver opens the service panel of a locked one, and a multitool in the open panel wipes the memory for a while. Its keypad is the
// window "SecureSafe": a first code of five digits sets the lock, the same code unlocks it, R locks it again.
CAPABILITIES(/obj/item/storage/secure)
	interface("SecureSafe")
	emag(then(PROC_REF(on_emag)))
	extend("storage.put_in", when(cond_not(nameof(locked))))
	extend("storage.refuse", when(cond_not(nameof(locked))))
	op("slice", item(/obj/item/melee/energy/blade), when(nameof(locked)), label("Slice open"), then(PROC_REF(slice_open)), passes())
	op("locked_click", item(/obj/item), priority(below("storage.put_in")), when(nameof(locked)), label("Put in"), passes())
	op("alt_open", hand(), answers(INTENT_TOGGLE), priority(above("storage.toggle_open")), label("Open"), then(PROC_REF(alt_open)))
	op("type", ui_act("type", arg("digit", schema_text(1))), then(PROC_REF(type_digit)))
	op("service_panel", tool(TOOL_SCREWDRIVER), when(nameof(locked)), label("Service panel"), then(PROC_REF(toggle_service_panel)))
	op("reset_memory", tool(TOOL_MULTITOOL), when(cond_all(nameof(locked), nameof(open))), wait(10 SECONDS), label("Reset memory"), then(PROC_REF(reset_memory)))

/obj/item/storage/secure/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The service panel is [src.open ? "open" : "closed"]."

/// What is drawn over the case: the sparks while the lock is shorted out, the shorted lock after it, the open light while a code has opened it.
/obj/item/storage/secure/draw(datum/look/look)
	. = ..()
	if(sparking)
		look.overlay(icon_sparking)
	else if(emagged)
		look.overlay(icon_locking)
	else if(!locked)
		look.overlay(icon_opened)

/// A locked one does not open for anybody who tries.
/obj/item/storage/secure/show_to(mob/user)
	if(locked)
		to_chat(user, span_warning("[src] is locked and cannot be opened!"))
		return
	return ..()

/// An energy blade slices through the lock; the click goes on.
/obj/item/storage/secure/proc/slice_open(datum/act/op/A)
	if(short_lock(A.actor, "You slice through the lock of \the [src]"))
		fx_sparks(src.loc, 5, FALSE)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		play_sfx(src, SFX_SPARKS)
	return OP_OK

/// An alt-click opens it, when it is unlocked.
/obj/item/storage/secure/proc/alt_open(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user))
		return OP_REFUSED
	if(locked)
		to_chat(user, span_warning("[src] is locked and cannot be opened!"))
	else
		open(user)
	add_fingerprint(user)
	return OP_OK

/// A screwdriver opens and closes the service panel of a locked one.
/obj/item/storage/secure/proc/toggle_service_panel(datum/act/op/A)
	set_open(!open)
	playsound(src, A.held.usesound, 50, TRUE)
	A.actor.show_message(span_notice("You [open ? "open" : "close"] the service panel."))
	return OP_OK

/// A multitool in the open panel wipes the lock's memory, or fails; the memory comes back after a while.
/obj/item/storage/secure/proc/reset_memory(datum/act/op/A)
	var/mob/user = A.actor
	user.show_message(span_notice("Now attempting to reset internal memory, please hold."), 1)
	if(prob(40))
		set_l_setshort(TRUE)
		set_l_set(FALSE)
		set_code("")
		user.show_message(span_notice("Internal memory reset. Please give it a few seconds to reinitialize."), 1)
		after(src, 8 SECONDS, PROC_REF(memory_reinitialized), key = "memory")
	else
		user.show_message(span_warning("Unable to reset internal memory."), 1)
	return OP_OK

/obj/item/storage/secure/MouseDrop(over_object, src_location, over_location)
	if (locked)
		src.add_fingerprint(usr)
		return
	..()

/// The keypad: the digits typed so far, the code that sets the lock, E to enter and R to lock.
/obj/item/storage/secure/ui_data(datum/act/eval/A)
	return list("locked" = locked, "code" = code, "emagged" = emagged, "l_setshort" = l_setshort, "l_set" = l_set)

/obj/item/storage/secure/proc/type_digit(datum/act/op/A, digit)
	var/mob/user = A.actor
	if(digit == "E")
		if ((src.l_set == 0) && (length(src.code) == 5) && (!src.l_setshort) && (src.code != "ERROR"))
			src.l_code = src.code
			set_l_set(1)
		else if ((src.code == src.l_code) && (src.emagged == 0) && (src.l_set == 1))
			set_locked(0)
			set_code(null)
		else
			set_code("ERROR")
	else
		if ((digit == "R") && (src.emagged == 0) && (!src.l_setshort))
			set_locked(1)
			set_code(null)
			src.close(user)
		else
			set_code("[src.code][digit]")
			if (length(src.code) > 5)
				set_code("ERROR")
	src.add_fingerprint(user)
	return OP_OK

/obj/item/storage/secure/proc/memory_reinitialized()
	set_l_setshort(FALSE)

/obj/item/storage/secure/proc/emag_spark_done(mob/user, feedback)
	set_sparking(FALSE)
	set_locked(0)
	to_chat(user, (feedback ? feedback : "You short out the lock of \the [src]."))

/obj/item/storage/secure/proc/on_emag(datum/act/op/A)
	short_lock(A.actor)
	return OP_OK

/// Shorts the lock out (an emag, or a blade slicing it). Returns 1 if it wasn't already.
/obj/item/storage/secure/proc/short_lock(mob/user, feedback)
	if(!emagged)
		set_emagged(1)
		set_sparking(TRUE)
		after(src, 0.6 SECONDS, PROC_REF(emag_spark_done), key = "spark", with = list(user, feedback), keeps_dead = TRUE)
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

// A briefcase's keypad is its use in hand.
CAPABILITIES(/obj/item/storage/secure/briefcase)
	configure(storage(max_size = ITEMSIZE_NORMAL))
	extend("ui_open", inputs(in_hand(), remote()))

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

CAPABILITIES(/obj/item/storage/secure/safe)
	configure(storage(refuses = list(/obj/item/storage/secure/briefcase), max_size = ITEMSIZE_LARGE))
