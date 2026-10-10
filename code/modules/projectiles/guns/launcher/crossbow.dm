//AMMUNITION

/obj/item/arrow
	name = "bolt"
	desc = "It's got a tip for you - get the point?"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "bolt"
	item_state = "bolt"
	drop_sound = SFX_ITEMS_DROP_SWORD
	pickup_sound = SFX_ITEMS_PICKUP_SWORD
	throwforce = 8
	w_class = ITEMSIZE_NORMAL
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE

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
	drop_sound = SFX_ITEMS_DROP_SWORD
	pickup_sound = SFX_ITEMS_PICKUP_SWORD

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


/obj/item/gun/launcher/crossbow/screwdriver_act(mob/user, obj/item/tool)
	if(cell())
		var/obj/item/C = cell()
		C.forceMove(get_turf(user))
		to_chat(user, span_notice("You jimmy [cell()] out of [src] with [tool]."))
		playsound(src, tool.usesound, 50, 1)
		rel_clear(src, nameof(cell))
	else
		to_chat(user, span_notice("[src] doesn't have a cell installed."))
	return ITEM_INTERACT_SUCCESS

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

/obj/item/crossbowframe/screwdriver_act(mob/user, obj/item/tool)
	if(buildstate == 5)
		to_chat(user, span_notice("You secure the crossbow's various parts."))
		playsound(src, tool.usesound, 50, 1)
		replace_with(src, /obj/item/gun/launcher/crossbow)
	return ITEM_INTERACT_SUCCESS

/obj/item/crossbowframe/welder_act(mob/user, obj/item/tool)
	if(buildstate == 1)
		var/obj/item/weldingtool/T = tool.get_welder()
		if(T.remove_fuel(0,user))
			if(!src || !T.isOn()) return ITEM_INTERACT_SUCCESS
			playsound(src, tool.usesound, 50, 1)
			to_chat(user, span_notice("You weld the rods into place."))
		set_buildstate(buildstate + 1)
	return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/crossbowframe)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/crossbowframe/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/stack/rods))
		if(buildstate == 0)
			var/obj/item/stack/rods/R = W
			if(R.use(3))
				to_chat(user, span_notice("You assemble a backbone of rods around the wooden stock."))
				set_buildstate(buildstate + 1)
			else
				to_chat(user, span_notice("You need at least three rods to complete this task."))
			return OP_PASS
	else if(istype(W, /obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/C = W
		if(buildstate == 2)
			if(C.use(5))
				to_chat(user, span_notice("You wire a crude cell mount into the top of the crossbow."))
				set_buildstate(buildstate + 1)
			else
				to_chat(user, span_notice("You need at least five segments of cable coil to complete this task."))
			return OP_PASS
		else if(buildstate == 4)
			if(C.use(5))
				to_chat(user, span_notice("You string a steel cable across the crossbow's lath."))
				set_buildstate(buildstate + 1)
			else
				to_chat(user, span_notice("You need at least five segments of cable coil to complete this task."))
			return OP_PASS
	else if(istype(W,/obj/item/stack/material) && W.get_material_name() == MAT_PLASTIC)
		if(buildstate == 3)
			var/obj/item/stack/material/P = W
			if(P.use(3))
				to_chat(user, span_notice("You assemble and install a heavy plastic lath onto the crossbow."))
				set_buildstate(buildstate + 1)
			else
				to_chat(user, span_notice("You need at least three plastic sheets to complete this task."))
			return OP_PASS
	else
		return OP_DECLINE
	return OP_PASS

/// Used for firing superheated rods. (a relation view: null once it is deleted).
/obj/item/gun/launcher/crossbow/proc/cell() as /obj/item/cell
	return cell

/obj/item/gun/launcher/crossbow/ownership()
	. = ..()
	. += owns(nameof(bolt), policy = OWN_CONTAINED)
