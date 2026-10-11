//AMMUNITION

/obj/item/arrow
	name = "bolt"
	desc = "It's got a tip for you - get the point?"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "bolt"
	item_state = "bolt"
	throwforce = 8
	w_class = ITEMSIZE_NORMAL
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE

CAPABILITIES(/obj/item/arrow)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SWORD, pickup = SFX_ITEMS_PICKUP_SWORD))

/obj/item/arrow/proc/removed() //Helper for metal rods falling apart.
	return

/obj/item/spike
	name = "alloy spike"
	desc = "It's about a foot of weird silver metal with a wicked point."
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	icon = 'icons/obj/weapons.dmi'
	icon_state = "metal-rod"
	item_state = "bolt"

CAPABILITIES(/obj/item/spike)
	configure(item_sounds(drop = SFX_ITEMS_DROP_SWORD, pickup = SFX_ITEMS_PICKUP_SWORD))

/obj/item/arrow/quill
	name = "alien quill"
	desc = "A wickedly barbed quill from some bizarre animal."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "quill"
	item_state = "quill"
	throwforce = 5

/obj/item/arrow/rod
	name = "metal rod"
	desc = "Don't cry for me, Orithena."
	icon_state = "metal-rod"

/obj/item/arrow/rod/removed(mob/user)
	if(throwforce == 15) // The rod has been superheated - we don't want it to be useable when removed from the bow.
		to_chat(user , "[src] shatters into a scattering of overstressed metal shards as it leaves the crossbow.")
		var/obj/item/material/shard/shrapnel/S = new()
		S.forceMove(get_turf(src))
		consume(src, user)

/obj/item/gun/launcher/crossbow
	name = "powered crossbow"
	desc = "A 2320AD twist on an old classic. Pick up that can."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "crossbow"
	item_state = "crossbow-solid"
	fire_sound = SFX_WEAPONS_PUNCHMISS // TODO: Decent THWOK noise.
	fire_sound_text = "a solid thunk"
	fire_delay = 25
	slot_flags = SLOT_BACK

	var/obj/item/bolt
	var/tension = 0                         // Current draw on the bow.
	var/max_tension = 5                     // Highest possible tension.
	var/release_speed = 5                   // Speed per unit of tension.
	var/tmp/obj/item/cell/cell	// Used for firing superheated rods.
	var/current_user                        // Used to check if the crossbow has changed hands since being drawn.
	w_class = ITEMSIZE_HUGE //.

	///Var for attack_self chain
	var/is_bow = FALSE
	special_handling = TRUE
TRACKED(/obj/item/gun/launcher/crossbow, tension)

// Drawing the string is one op that waits a notch at a time, 2.5 seconds each, until the string is at its maximum tension; leaving, firing or
// losing the bolt ends it with the notches drawn so far, and the string relaxes.
CAPABILITIES(/obj/item/gun/launcher/crossbow)
	op("screwdriver_work", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_PART + 2), wait(0), then(PROC_REF(screwdriver_worked)))
	op("draw_string", ai(), needs(req(PROC_REF(draw_holds), because = MSG(req_silent))), wait(2.5 SECONDS, repeats = PROC_REF(draw_more), after_step = PROC_REF(draw_notch)), on_interrupt(PROC_REF(draw_relaxed)))

/obj/item/gun/launcher/crossbow/update_release_force()
	release_force = tension*release_speed

/obj/item/gun/launcher/crossbow/consume_next_projectile(mob/user=null)
	if(tension <= 0)
		to_chat(user, span_warning("\The [src] is not drawn back!"))
		return null
	return bolt

/obj/item/gun/launcher/crossbow/handle_post_fire(mob/user, atom/target)
	rel_take(src, nameof(bolt))
	set_tension(0)
	..()

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/crossbow/gun_operate(datum/act/op/A, callback)
	var/mob/living/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	if(is_bow)
		return OP_DECLINE
	if(tension)
		if(bolt)
			act_message(user, src, MSG_SELF("You relax the tension on %T%'s string and remove [bolt]."), \
				MSG_OTHERS("%U% relaxes the tension on %T%'s string and removes [bolt]."))
			bolt.forceMove(get_turf(src))
			var/obj/item/arrow/removed_arrow = bolt
			rel_take(src, nameof(bolt))
			removed_arrow.removed(user)
		else
			act_message(user, src, MSG_SELF("You relax the tension on %T%'s string."), MSG_OTHERS("%U% relaxes the tension on %T%'s string."))
		set_tension(0)
	else
		draw_string(user)

/obj/item/gun/launcher/crossbow/proc/draw_string(mob/user as mob)

	if(!bolt)
		to_chat(user, "You don't have anything nocked to [src].")
		return

	if(user.restrained())
		return

	current_user = user
	act_message(user, src, MSG_SELF(span_notice("You begin to draw back the string of %T%.")), MSG_OTHERS("%U% begins to draw back the string of %T%."))
	set_tension(1)
	// crossbow strings don't just magically pull back on their own: one notch of tension every 2.5 seconds up to max_tension
	var/datum/op_result/drawing = perform_op(user, src, "draw_string", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
	if(drawing.outcome == ACT_REFUSED)
		set_tension(0)

/// The bolt is nocked and the string is drawn at all (the crossbow is the op's held item: leaving the hands that drew it stops the draw).
/obj/item/gun/launcher/crossbow/proc/draw_holds(datum/act/op/A)
	return bolt && tension ? null : MSG(req_silent)

/// Another notch follows while the string is short of its maximum tension.
/obj/item/gun/launcher/crossbow/proc/draw_more(datum/act/op/A)
	return tension < max_tension

/obj/item/gun/launcher/crossbow/proc/draw_relaxed(datum/act/op/A)
	if(!tension)
		return // fired or relaxed already: nothing left to let go of
	act_message(A.actor, src, others = "%U% stops drawing and relaxes the string of %T%.", \
		blind = span_warning("You stop drawing back and relax the string of %T%."))
	set_tension(0)

/// One notch drawn.
/obj/item/gun/launcher/crossbow/proc/draw_notch(datum/act/op/A)
	var/mob/user = A.actor
	set_tension(tension + 1)

	if(tension >= max_tension)
		set_tension(max_tension)
		to_chat(user, "[src] clunks as you draw the string to its maximum tension!")
		return

	act_message(user, src, MSG_SELF(span_notice("You continue drawing back the string of %T%!")), MSG_OTHERS("%U% draws back the string of %T%!"))

/obj/item/gun/launcher/crossbow/proc/increase_tension(mob/user as mob)

	if(!bolt || !tension || current_user != user) //Arrow has been fired, bow has been relaxed or user has changed.
		return


/// Its own screwdriver work, ahead of the gun's DNA lock removal.
/obj/item/gun/launcher/crossbow/proc/screwdriver_worked(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(cell())
		var/obj/item/C = cell()
		C.forceMove(get_turf(user))
		to_chat(user, span_notice("You jimmy [cell()] out of [src] with [tool]."))
		playsound(src, sounds_of(tool).use, 50, 1)
		rel_clear(src, nameof(cell))
	else
		to_chat(user, span_notice("[src] doesn't have a cell installed."))
	return OP_OK

/// Old attackby.
/obj/item/gun/launcher/crossbow/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	. = OP_PASS
	if(!bolt)
		if (istype(W,/obj/item/arrow))
			if(!move_into(src, nameof(src.bolt), W, user))
				return
			act_message(user, src, MSG_SELF("You slide [bolt] into %T%."), MSG_OTHERS("%U% slides [bolt] into %T%."))
			return
		else if(istype(W,/obj/item/stack/rods))
			var/obj/item/stack/rods/R = W
			if (R.use(1))
				rel_set(src, nameof(bolt), new /obj/item/arrow/rod(src))
				bolt.add_fingerprint(user)
				bolt.forceMove(src)
				act_message(user, src, MSG_SELF("You jam [bolt] into %T%."), MSG_OTHERS("%U% jams [bolt] into %T%."))
				superheat_rod(user)
			return

	if(istype(W, /obj/item/cell))
		if(!cell())
			user.drop_item()
			rel_set(src, nameof(cell), W)
			cell().forceMove(src)
			to_chat(user, span_notice("You jam [cell()] into [src] and wire it to the firing coil."))
			superheat_rod(user)
		else
			to_chat(user, span_notice("[src] already has a cell installed."))

	else
		return ..()

/obj/item/gun/launcher/crossbow/proc/superheat_rod(mob/user)
	if(!user || !cell() || !bolt) return
	if(cell().charge < 500) return
	if(bolt.throwforce >= 15) return
	if(!istype(bolt,/obj/item/arrow/rod)) return

	to_chat(user, span_notice("[bolt] plinks and crackles as it begins to glow red-hot."))
	bolt.throwforce = 15
	bolt.icon_state = "metal-rod-superheated"
	cell().use(500)

/// Suffix for the declared icon_state: drawn, nocked or idle.
/obj/item/gun/launcher/crossbow/proc/appearance_draw_suffix()
	if(tension > 1)
		return "-drawn"
	if(bolt)
		return "-nocked"
	return ""
/// The look (the draw sweep: from its template).
/obj/item/gun/launcher/crossbow/draw(datum/look/look)
	..()
	look.state("crossbow[appearance_draw_suffix()]")


// Crossbow construction.
/obj/item/crossbowframe
	name = "crossbow frame"
	desc = "A half-finished crossbow."
	icon_state = "crossbowframe0"
	item_state = "crossbow-solid"

	var/buildstate = 0

TRACKED(/obj/item/crossbowframe, buildstate)

/// The look (the draw sweep: from its template).
/obj/item/crossbowframe/draw(datum/look/look)
	..()
	look.state("crossbowframe[buildstate]")

/obj/item/crossbowframe/examine(mob/user)
	. = ..()
	switch(buildstate)
		if(1)
			. += "It has a loose rod frame in place."
		if(2)
			. += "It has a steel backbone welded in place."
		if(3)
			. += "It has a steel backbone and a cell mount installed."
		if(4)
			. += "It has a steel backbone, plastic lath and a cell mount installed."
		if(5)
			. += "It has a steel cable loosely strung across the lath."

MSG_DEF_SELF(crossbow_frame/rods, "You assemble a backbone of rods around the wooden stock.")
MSG_DEF_SELF(crossbow_frame/welded, "You weld the rods into place.")
MSG_DEF_SELF(crossbow_frame/mount, "You wire a crude cell mount into the top of the crossbow.")
MSG_DEF_SELF(crossbow_frame/lath, "You assemble and install a heavy plastic lath onto the crossbow.")
MSG_DEF_SELF(crossbow_frame/strung, "You string a steel cable across the crossbow's lath.")
MSG_DEF_SELF(crossbow_frame/secured, "You secure the crossbow's various parts.")

CAPABILITIES(/obj/item/crossbowframe)
	// the stock, rods, a welded backbone, a cell mount, a plastic lath, the string; the screwdriver finishes it
	stages(nameof(buildstate),
		stage_step(0, 1, stack(/obj/item/stack/rods, 3), label("Assemble the rod backbone"), wait(0), says(MSG(crossbow_frame/rods))),
		stage_step(1, 2, lit_welder(fuel = 0), label("Weld the rods"), wait(0), says(MSG(crossbow_frame/welded)), then(PROC_REF(tool_sounds))),
		stage_step(2, 3, stack(/obj/item/stack/cable_coil, 5), label("Wire a cell mount"), wait(0), says(MSG(crossbow_frame/mount))),
		stage_step(3, 4, stack(/obj/item/stack/material/plastic, 3), label("Install a plastic lath"), wait(0), says(MSG(crossbow_frame/lath))),
		stage_step(4, 5, stack(/obj/item/stack/cable_coil, 5), label("String the cable"), wait(0), says(MSG(crossbow_frame/strung))))
	op("finish", tool(TOOL_SCREWDRIVER), label("Secure the parts"), when(req_stage(nameof(buildstate), 5)), wait(0), says(MSG(crossbow_frame/secured)), then(PROC_REF(finished)))

/obj/item/crossbowframe/proc/tool_sounds(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 50, 1)
	return OP_OK

/// Secured, the frame is a crossbow.
/obj/item/crossbowframe/proc/finished(datum/act/op/A)
	playsound(src, sounds_of(A.held).use, 50, 1)
	replace_with(src, /obj/item/gun/launcher/crossbow)
	return OP_OK

/// Used for firing superheated rods. (a relation view: null once it is deleted).
/obj/item/gun/launcher/crossbow/proc/cell() as /obj/item/cell
	return cell

/obj/item/gun/launcher/crossbow/ownership()
	. = ..()
	. += owns(nameof(bolt), policy = OWN_CONTAINED)
