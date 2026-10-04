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

#define SCROLL_TELEPORT "Teleport"
#define SCROLL_CANCEL "Cancel"

CAPABILITIES(/obj/item/teleportation_scroll)
	op("self", in_hand(), needs(req(PROC_REF(can_read), because = MSG(scroll/unreadable))), then(PROC_REF(interaction_self)))

MSG_DEF_SELF(scroll/unreadable, "you stare at the scroll but cannot make sense of the markings")

/// Requirement: only a wizard can make sense of the markings.
/obj/item/teleportation_scroll/proc/can_read(datum/act/op/A)
	var/mob/user = A.actor
	return !user.mind || GLOB.wizards.is_antagonist(user.mind) // ALLOW(reads): the reader's mind is read when the scroll is used, never from a cached menu

/// Old attack_self.
/obj/item/teleportation_scroll/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	// single-action panel; a two-button question with the existing
	// uses count is the right primitive.
	user.set_machine(src)
	open_request(src, /datum/prompt/choice, PROC_REF(scroll_answered), answerer = user, title = "Teleportation Scroll", question = "You have [uses] uses left.\n\nKind regards, the Wizards Federation.\nP.S. Don't forget to bring your gear, you'll need it to cast most spells.", choices = list(SCROLL_TELEPORT, SCROLL_CANCEL), buttons = TRUE, ask_flags = ASK_CARRIED | ASK_CAPABLE | ASK_CONSCIOUS, timeout = 0)
	return OP_OK

/obj/item/teleportation_scroll/proc/scroll_answered(datum/act/request/A)
	if(!A.answer || A.answer.answer_value != SCROLL_TELEPORT)
		return
	var/mob/living/carbon/human/user = A.request.answerer
	if(ishuman(user) && !user.restrained() && uses >= 1)
		teleportscroll(user)


/obj/item/teleportation_scroll/proc/teleportscroll(mob/user)
	open_request(src, /datum/prompt/choice, PROC_REF(area_chosen), answerer = user, title = "Teleportation Scroll", question = "Area to jump to:", choices = GLOB.teleportlocs, ask_flags = ASK_CARRIED | ASK_CAPABLE | ASK_CONSCIOUS, timeout = 0)

/obj/item/teleportation_scroll/proc/area_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/area/thearea = GLOB.teleportlocs[A.answer.answer_value]
	if(!thearea || uses < 1)
		return

	if (user.restrained())
		return
	if(!((user == loc || (in_range(src, user) && istype(src.loc, /turf)))))
		return

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
		return

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
	src.uses -= 1

#undef SCROLL_TELEPORT
#undef SCROLL_CANCEL
