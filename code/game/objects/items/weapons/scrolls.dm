/obj/item/teleportation_scroll
	name = "scroll of teleportation"
	desc = "A scroll for moving around."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "scroll"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_books.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_books.dmi'
		)
	var/uses = 4.0
	w_class = ITEMSIZE_TINY
	item_state = "paper"
	throw_speed = 4
	throw_range = 20

TRACKED(/obj/item/teleportation_scroll, uses)

CAPABILITIES(/obj/item/teleportation_scroll)
	// the old attack_self: how many uses are left, then where to (a person, free, with a use left)
	op("read", in_hand(), needs(req_bool(PROC_REF(can_read), because = MSG(teleportation_scroll/unreadable))),
		asks(/datum/prompt/choice, fields = list("title" = "Teleportation Scroll", "question" = computed(PROC_REF(uses_question)), "choices" = list("Teleport", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "teleport"),
		asks(/datum/prompt/choice, fields = list("title" = "Teleportation Scroll", "question" = "Area to jump to:", "choices" = computed(PROC_REF(area_choices)), "timeout" = 0), step = "area", when = PROC_REF(teleport_chosen)),
		then(PROC_REF(area_chosen)))

/// Requirement: only a wizard (or a mindless body) can make sense of the markings.
/obj/item/teleportation_scroll/proc/can_read(datum/act/op/A)
	return reads_wizard_markings(A.actor)

/// Can `user` read a wizard's markings?
/proc/reads_wizard_markings(mob/user)
	READS_FROM() // a mind's antagonist roles are not round state an op could watch
	return !user.mind || GLOB.wizards.is_antagonist(user.mind)

MSG_DEF_SELF(teleportation_scroll/unreadable, "You stare at the scroll but cannot make sense of the markings.")

/obj/item/teleportation_scroll/proc/uses_question(datum/act/A)
	return "You have [uses] uses left.\n\nKind regards, the Wizards Federation.\nP.S. Don't forget to bring your gear, you'll need it to cast most spells."

/obj/item/teleportation_scroll/proc/area_choices(datum/act/A)
	return GLOB.teleportlocs

/// "Teleport", by a free person, with a use left: the area comes next.
/obj/item/teleportation_scroll/proc/teleport_chosen(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["teleport"]
	return R?.value == "Teleport" && scroll_user_free(A.actor) && uses >= 1

/proc/scroll_user_free(mob/user)
	READS_FROM() // a restraint is asked when the question is
	return ishuman(user) && !user.restrained()

/// The scroll jumps its reader to a clear tile of the chosen area, in a puff of smoke.
/obj/item/teleportation_scroll/proc/area_chosen(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["area"]
	if(!R)
		return OP_OK
	var/mob/user = A.actor
	user.set_machine(src)
	var/area/thearea = GLOB.teleportlocs[R.value]
	if(!thearea || uses < 1)
		return OP_OK

	if (user.restrained())
		return OP_OK
	if(!((user == loc || (in_range(src, user) && istype(src.loc, /turf)))))
		return OP_OK

	var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
	smoke.set_up(5, 0, user.loc)
	smoke.attach(user)
	smoke.start()
	var/list/L = list()
	for(var/turf/T in get_area_turfs(thearea.type))
		if(!T.density)
			var/clear = 1
			for(var/obj/O in contents_of(T))
				if(O.density)
					clear = 0
					break
			if(clear)
				L+=T

	if(!L.len)
		to_chat(user, span_warning("The spell matrix was unable to locate a suitable teleport destination for an unknown reason. Sorry."))
		return OP_OK

	if(user && user?.buckled_to())
		var/atom/movable/_tmp_buck_8 = user?.buckled_to()
		_tmp_buck_8.unbuckle_mob( user, TRUE)

	var/list/tempL = L
	var/attempt = null
	var/success = 0
	while(tempL.len)
		attempt = pick(tempL)
		success = user.forceMove(attempt)
		if(!success)
			tempL.Remove(attempt)
		else
			break

	if(!success)
		to_chat(user, span_warning("The spell matrix was unable to locate a suitable teleport destination, because the destination area is entirely obstructed. Sorry."))
		user.forceMove(pick(L))

	smoke.start()
	set_uses(uses - 1)
	return OP_OK

