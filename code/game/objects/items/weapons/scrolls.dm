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

DECLARE_INTERACTIONS(/obj/item/teleportation_scroll, INTERACT_USE(null, PROC_REF(interaction_self), REQ_TARGET_STATE(/obj/item/teleportation_scroll/proc/can_read)))

/// Requirement: only a wizard can make sense of the markings.
/obj/item/teleportation_scroll/proc/can_read(mob/user, atom/target, obj/item/held)
	if(user.mind && !GLOB.wizards.is_antagonist(user.mind))
		return "you stare at the scroll but cannot make sense of the markings"
	return TRUE

/// Old attack_self.
/obj/item/teleportation_scroll/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	// single-action panel; tgui_alert with the existing
	// uses count is the right primitive.
	user.set_machine(src)
	om_ask(user, /datum/om/prompt/confirm, PROC_REF(scroll_answered), title = "Teleportation Scroll", yes_text = "Teleport", no_text = "Cancel", ask_flags = ASK_CARRIED | ASK_CAPABLE | ASK_CONSCIOUS, message = "You have [uses] uses left.\n\nKind regards, the Wizards Federation.\nP.S. Don't forget to bring your gear, you'll need it to cast most spells.")
	return TRUE

/obj/item/teleportation_scroll/proc/scroll_answered(datum/om/prompt/confirm/ask)
	var/mob/living/carbon/human/user = ask.answerer
	if(ishuman(user) && !user.restrained() && uses >= 1)
		teleportscroll(user)


/obj/item/teleportation_scroll/proc/teleportscroll(mob/user)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(area_chosen), title = "Teleportation Scroll", message = "Area to jump to:", choices = GLOB.teleportlocs, ask_flags = ASK_CARRIED | ASK_CAPABLE | ASK_CONSCIOUS)

/obj/item/teleportation_scroll/proc/area_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/area/thearea = GLOB.teleportlocs[ask.choice]
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
