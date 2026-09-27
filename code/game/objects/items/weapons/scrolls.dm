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

/obj/item/teleportation_scroll/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if((user.mind && !GLOB.wizards.is_antagonist(user.mind)))
		to_chat(user, span_warning("You stare at the scroll but cannot make sense of the markings!"))
		return

	// single-action panel; tgui_alert with the existing
	// uses count is the right primitive.
	user.set_machine(src)
	om_prompt(src, user, list("message" = "You have [uses] uses left.\n\nKind regards, the Wizards Federation.\nP.S. Don't forget to bring your gear, you'll need it to cast most spells.", "title" = "Teleportation Scroll", "choices" = list("Teleport", "Cancel"), "requires" = PROMPT_HELD), PROC_REF(scroll_answered))

/obj/item/teleportation_scroll/proc/scroll_answered(mob/living/carbon/human/user, choice, datum/om/prompt/ask)
	if(choice == "Teleport" && ishuman(user) && !user.stat && !user.restrained() && uses >= 1)
		teleportscroll(user)

/obj/item/teleportation_scroll/Topic(href, href_list)
	..()
	if (usr.stat || usr.restrained() || src.loc != usr)
		return
	var/mob/living/carbon/human/H = usr
	if (!ishuman(H))
		return 1
	if ((usr == src.loc || (in_range(src, usr) && istype(src.loc, /turf))))
		usr.set_machine(src)
		if (href_list["spell_teleport"])
			if (src.uses >= 1)
				teleportscroll(H)
				return
	attack_self(H)
	return

/obj/item/teleportation_scroll/proc/teleportscroll(mob/user)
	om_prompt(src, user, list("kind" = "list", "message" = "Area to jump to:", "title" = "Teleportation Scroll", "choices" = GLOB.teleportlocs, "requires" = PROMPT_HELD), PROC_REF(area_chosen))

/obj/item/teleportation_scroll/proc/area_chosen(mob/user, A, datum/om/prompt/ask)
	var/area/thearea = GLOB.teleportlocs[A]
	if(!thearea || uses < 1)
		return

	if (user.stat || user.restrained())
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
			for(var/obj/O in T)
				if(O.density)
					clear = 0
					break
			if(clear)
				L+=T

	if(!L.len)
		to_chat(user, span_warning("The spell matrix was unable to locate a suitable teleport destination for an unknown reason. Sorry."))
		return

	if(user && BUCKLED(user))
		var/atom/movable/_tmp_buck_8 = BUCKLED(user)
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
