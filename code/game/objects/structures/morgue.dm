/* Morgue stuff
 * Contains:
 *		Morgue
 *		Morgue trays
 *		Creamatorium
 *		Creamatorium trays
 */

/*
 * Morgue
 */

/obj/structure/morgue
	name = "morgue"
	desc = "A refrigerated unit used to store bodies, or for surreptitious naps."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "morgue1"
	dir = EAST
	density = TRUE
	var/obj/structure/m_tray/connected = null
	var/list/occupants
	anchored = TRUE
	unacidable = TRUE

CAPABILITIES(/obj/structure/morgue)
	blast_contents()
	owns_one(nameof(connected), /obj/structure/m_tray)
	op("use", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("label", item(/obj/item/pen), label("Use"), asks(/datum/prompt/text, fields = list("title" = "name", "question" = computed(PROC_REF(label_question)), "name_text" = TRUE, "timeout" = 0)), then(PROC_REF(label_entered)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))


/obj/structure/morgue/proc/get_occupants()
	rel_clear(src, nameof(occupants))
	for(var/mob/living/carbon/human/H in contents)
		rel_add(src, nameof(occupants), H)
	for(var/obj/structure/closet/body_bag/B in contents)
		for(var/mob/living/carbon/human/bagged as anything in B.get_occupants())
			rel_add(src, nameof(occupants), bagged)

/obj/structure/morgue/proc/update(broadcast=0)
	if (src.connected)
		src.icon_state = "morgue0"
	else
		if (contents_count(src))
			src.icon_state = "morgue2"
			get_occupants()
			for (var/mob/living/carbon/human/H in occupants)
				if(HAS_SYNTHETIC_BIOLOGY(H) || H.suiciding || !H.ckey || !H.client || (H.has_mutation(NOCLONE)) || (H.species && H.species.flags & NO_SLEEVE))
					src.icon_state = "morgue2"
					break
				else
					src.icon_state = "morgue3"
					if(broadcast)
						GLOB.global_announcer.autosay("[src] was able to establish a mental interface with occupant.", "[src]", "Medical")
		else
			src.icon_state = "morgue1"
	return

/obj/structure/morgue/atom_destruction(damage_flag)
	for(var/atom/movable/A as anything in contents)
		A.forceMove(loc)
	return ..()

/obj/structure/morgue
	silicon_use = ROBOT_USE_HAND_ADJACENT

/// Old attack_hand: pull the tray out, or push it back in.
/obj/structure/morgue/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (src.connected)
		close()
	else
		open()
	src.add_fingerprint(user)
	update()
	return OP_OK

/obj/structure/morgue/proc/close()
	for(var/atom/movable/A as mob|obj in src.connected.loc)
		if (!( A.anchored ))
			A.forceMove(src)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	rel_clear(src, nameof(connected))

/obj/structure/morgue/proc/open()
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	rel_set(src, nameof(connected), new /obj/structure/m_tray( src.loc ))
	rel_set(connected, nameof(connected.connected), src)
	step(src.connected, src.dir)
	src.connected.layer = OBJ_LAYER
	var/turf/T = get_step(src, src.dir)
	if (T.contents.Find(src.connected))
		src.icon_state = "morgue0"
		for(var/atom/movable/A as mob|obj in contents_of(src))
			A.forceMove(src.connected.loc)
		src.connected.icon_state = "morguet"
		src.connected.set_dir(src.dir)
	else
		rel_clear(src, nameof(connected))


/// Old attackby: a held thing leaves a print and does nothing else (a pen relabels it: the "label" op).
/obj/structure/morgue/proc/interaction_item(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// The question a pen asks: the morgue's own name as the title.
/obj/structure/morgue/proc/label_question(datum/act/A)
	return "What would you like the label to be?"

/// A pen relabels it (the pen held throughout, still beside it).
/obj/structure/morgue/proc/label_entered(datum/act/op/A)
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	var/t = sanitizeSafe(R.value, MAX_NAME_LEN)
	if (t)
		src.name = text("Morgue- '[]'", t)
	else
		src.name = "Morgue"
	return OP_OK

/obj/structure/morgue/relaymove(mob/user as mob)
	if (user.stat)
		return
	if (user in src.occupants)
		open()

/*
 * Morgue tray
 */
/obj/structure/m_tray
	name = "morgue tray"
	desc = "Apply corpse before closing."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "morguet"
	density = TRUE
	plane = TURF_PLANE
	var/obj/structure/morgue/connected = null
	anchored = TRUE
	throwpass = 1

// The morgue owns its tray (implicit OWN, deleted with it); the tray names its morgue (one-sided REL).

/obj/structure/m_tray
	silicon_use = ROBOT_USE_HAND_ADJACENT

CAPABILITIES(/obj/structure/m_tray)
	op("push_in", hand(), label("Push in"), then(PROC_REF(interaction_hand)))
	op("place", item(/atom/movable), gesture(GESTURE_DRAG), label("Place on tray"), then(PROC_REF(interaction_drag)))

/// Old attack_hand: push the tray (and what lies on it) back into its morgue.
/obj/structure/m_tray/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (src.connected)
		for(var/atom/movable/AM as mob|obj in src.loc)
			if (!( AM.anchored ))
				AM.forceMove(src.connected)
			//Foreach goto(26)
		var/obj/structure/morgue/M = connected
		add_fingerprint(user)
		own_clear(M, nameof(M.connected), OWN_DELETE) // the morgue owns this tray: deletes src
		M.update()
	return OP_OK

/// Old MouseDrop_T: a body or a body bag dragged onto the tray is laid on it.
/obj/structure/m_tray/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/O = A.held
	if ((!( istype(O, /atom/movable) ) || O.anchored || get_dist(user, src) > 1 || get_dist(user, O) > 1 || user.contents.Find(src) || user.contents.Find(O)))
		return OP_PASS
	if (!ismob(O) && !istype(O, /obj/structure/closet/body_bag))
		return OP_PASS
	if (!ismob(user) || user.stat || user.lying || user.has_status(STAT_STUNNED))
		return OP_PASS
	O.forceMove(src.loc)
	if (user != O)
		for(var/mob/B in viewers(user, 3))
			if ((B.client && !( B.blinded )))
				to_chat(B, span_warning("\The [user] stuffs [O] into [src]!"))
	return OP_PASS

/*
 * Crematorium
 */

REGISTRY_MEMBERSHIP(/obj/structure/morgue/crematorium, REGISTRY_CREMATORIUMS)

/obj/structure/morgue/crematorium
	name = "crematorium"
	desc = "A human incinerator. Works well on barbeque nights."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "crema1"
	var/cremating = 0
	var/id = 1
	var/locked = 0

TRACKED(/obj/structure/morgue/crematorium, cremating)

// the crematorium's own Use replaces the morgue's (its tray is a crematorium tray, and it is locked while it burns)
CAPABILITIES(/obj/structure/morgue/crematorium)
	without("use")
	op("crema_use", hand(), label("Use"), needs(req_is(nameof(cremating), FALSE, because = MSG(crematorium/locked))), then(PROC_REF(interaction_crema_hand)))

MSG_DEF_SELF(crematorium/locked, "It's locked.")

/obj/structure/morgue/crematorium/update()
	if (src.connected)
		src.icon_state = "crema0"
	else
		if (contents_count(src))
			src.icon_state = "crema2"
		else
			src.icon_state = "crema1"
	return

/// Old attack_hand: pull the crematorium tray out or push it in (not while it burns).
/obj/structure/morgue/crematorium/proc/interaction_crema_hand(datum/act/op/A)
	var/mob/user = A.actor
	if ((src.connected) && (src.locked == 0))
		for(var/atom/movable/AM as mob|obj in src.connected.loc)
			if (!( AM.anchored ))
				AM.forceMove(src)
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		rel_clear(src, nameof(connected))
	else if (src.locked == 0)
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		rel_set(src, nameof(connected), new /obj/structure/m_tray/c_tray( src.loc ))
		rel_set(connected, nameof(connected.connected), src)
		step(src.connected, dir)
		src.connected.layer = OBJ_LAYER
		var/turf/T = get_step(src, dir)
		if (T.contents.Find(src.connected))
			src.icon_state = "crema0"
			for(var/atom/movable/AM as mob|obj in contents_of(src))
				AM.forceMove(src.connected.loc)
			src.connected.icon_state = "cremat"
		else
			rel_clear(src, nameof(connected))
	src.add_fingerprint(user)
	update()
	return OP_OK

/obj/structure/morgue/crematorium/label_entered(datum/act/op/A)
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	var/t = sanitizeSafe(R.value, MAX_NAME_LEN)
	if (t)
		src.name = text("Crematorium- '[]'", t)
	else
		src.name = "Crematorium"
	return OP_OK

/obj/structure/morgue/crematorium/relaymove(mob/user as mob)
	if (user.stat || locked)
		return
	rel_set(src, nameof(connected), new /obj/structure/m_tray/c_tray( src.loc ))
	rel_set(connected, nameof(connected.connected), src)
	step(src.connected, EAST)
	src.connected.layer = OBJ_LAYER
	var/turf/T = get_step(src, EAST)
	if (T.contents.Find(src.connected))
		src.icon_state = "crema0"
		for(var/atom/movable/A as mob|obj in contents_of(src))
			A.forceMove(src.connected.loc)
		src.connected.icon_state = "cremat"
	else
		rel_clear(src, nameof(connected))
	return

/obj/structure/morgue/crematorium/proc/cremation_done()
	set_cremating(0)
	locked = 0
	play_sfx(src, SFX_MACHINES_DING)

/obj/structure/morgue/crematorium/proc/cremate(atom/A, mob/user as mob)
	if(cremating)
		return //don't let you cremate something twice or w/e

	if(contents_count(src) <= 0)
		for (var/mob/M in viewers(src))
			to_chat(M, span_warning("You hear a hollow crackle."))
			return

	else
		if(!isemptylist(src.search_contents_for(/obj/item/disk/nuclear)))
			to_chat(user, "You get the feeling that you shouldn't cremate one of the items in the cremator.")
			return

		for (var/mob/M in viewers(src))
			to_chat(M, span_warning("You hear a roar as the crematorium activates."))

		set_cremating(1)
		locked = 1

		for(var/mob/living/M in contents)
			if (M.stat!=2)
				if (!iscarbon(M))
					M.emote("scream")
				else
					var/mob/living/carbon/C = M
					if (C.can_feel_pain())
						C.emote("scream")

			M.death(1)
			M.ghostize()
			consume(M)

		for(var/obj/O in contents) //obj instead of obj/item so that bodybags and ashes get destroyed. We dont want tons and tons of ash piling up
			consume(O)

		new /obj/effect/decal/cleanable/ash(src)
		after(src, 3 SECONDS, PROC_REF(cremation_done))
	return

/*
 * Crematorium tray
 */
/obj/structure/m_tray/c_tray
	name = "crematorium tray"
	desc = "Apply body before burning."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "cremat"

/obj/machinery/button/crematorium
	name = "crematorium igniter"
	desc = "Burn baby burn!"
	icon = 'icons/obj/power.dmi'
	icon_state = "crema_switch"
	req_access = list(ACCESS_CREMATORIUM)
	id = 1

CAPABILITIES(/obj/machinery/button/crematorium)
	op("trigger", hand(), label("Trigger"), needs(req_access()), then(PROC_REF(interaction_trigger)))

/// Old attack_hand: light every crematorium with this button's id (crematorium access only).
/obj/machinery/button/crematorium/proc/interaction_trigger(datum/act/op/A)
	var/mob/user = A.actor
	for (var/obj/structure/morgue/crematorium/C in REGISTRY_MEMBERS(REGISTRY_CREMATORIUMS))
		if (C.id == id)
			if (!C.cremating)
				C.cremate(null, user)
	return OP_OK

/obj/structure/morgue/crematorium/vr
	var/static/list/allowed_items = list(/obj/item/organ,
			/obj/item/implant,
			/obj/item/material/shard/shrapnel,
			/mob/living)

/obj/structure/morgue/crematorium/vr/cremate(atom/A, mob/user as mob)
	if(cremating)
		return //don't let you cremate something twice or w/e

	if(contents_count(src) <= 0)
		for (var/mob/M in viewers(src))
			M.show_message(span_warning("You hear a hollow crackle."), 1)
			return
	else
		if(!isemptylist(src.search_contents_for(/obj/item/disk/nuclear)))
			to_chat(user, "You get the feeling that you shouldn't cremate one of the items in the cremator.")
			return

		for(var/I in contents)
			if(!is_type_in_list(I, allowed_items))
				to_chat(user, span_notice("\The [src] cannot cremate while there are items inside!"))
				return
			if(isliving(I))
				var/mob/living/cremated = I
				for(var/Z in contents_of(cremated))
					if(!is_type_in_list(Z, allowed_items))
						to_chat(user, span_notice("\The [src] cannot cremate while there are items inside!"))
						return

		for (var/mob/M in viewers(src))
			M.show_message(span_warning("You hear a roar as the crematorium activates."), 1)

		set_cremating(1)
		locked = 1

		for(var/mob/living/M in contents)
			if (M.stat!=2)
				if (!iscarbon(M))
					M.emote("scream")
				else
					var/mob/living/carbon/C = M
					if (C.can_feel_pain())
						C.emote("scream")

			M.death(1)
			M.ghostize()
			consume(M)

		for(var/obj/O in contents) //obj instead of obj/item so that bodybags and ashes get destroyed. We dont want tons and tons of ash piling up
			consume(O)

		new /obj/effect/decal/cleanable/ash(src)
		after(src, 3 SECONDS, PROC_REF(cremation_done))
	return
