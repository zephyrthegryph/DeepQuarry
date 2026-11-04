/*
 * Trick revolver
 */
/obj/item/toy/russian_revolver/trick_revolver
	name = "\improper .357 revolver"
	desc = "A suspicious revolver. Uses .357 ammo."
	icon = 'icons/obj/toy.dmi'
	icon_state = "revolver"
	max_shots = 1
	var/fake_bullets = 0

CAPABILITIES(/obj/item/toy/russian_revolver/trick_revolver)
	rolls(nameof(fake_bullets), range_of(2, 7))

/obj/item/toy/russian_revolver/trick_revolver/examine(mob/user)
	. = ..()
	. += "Has [fake_bullets] round\s remaining."
	. += "[fake_bullets] of those are live rounds."

/obj/item/toy/russian_revolver/trick_revolver/post_shot(user)
	to_chat(user, span_danger("[src] did look pretty dodgy!"))
	play_sfx(src, SFX_ITEMS_CONFETTI, vary = TRUE)
	var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
	s.set_up(5, 1, src)
	s.start()
	set_icon_state("shoot")
	after(src, 0.5 SECONDS, TYPE_PROC_REF(/atom, set_icon_state), with = list(initial(icon_state)))
