/obj/item/latexballon
	name = "latex glove"
	desc = "A latex glove, usually used as a balloon."
	icon = 'icons/obj/items.dmi'
	icon_state = "latexballon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
			)
	item_state = "lgloves"
	force = 0
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	throw_speed = 1
	throw_range = 15
	var/state
	var/datum/gas_mixture/air_contents = null

CAPABILITIES(/obj/item/latexballon)
	owns_one(nameof(air_contents), /datum/gas_mixture)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(balloon_blast))))
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(balloon_shot))))
	op("puncture", item(/obj/item), when(req_bool(PROC_REF(punctures))), passes(), then(PROC_REF(punctured)))

/obj/item/latexballon/proc/blow(obj/item/tank/tank)
	if (icon_state == "latexballon_bursted")
		return
	rel_set(src, nameof(air_contents), tank.remove_air_volume(3))
	icon_state = "latexballon_blow"
	item_state = "latexballon"

/obj/item/latexballon/proc/burst()
	if (!air_contents)
		return
	play_sfx(src, SFX_WEAPONS_GUNSHOT_OLD)
	icon_state = "latexballon_bursted"
	item_state = "lgloves"
	loc.assume_air(air_contents)

/// A blast bursts the balloon and still lands.
/obj/item/latexballon/proc/balloon_blast(datum/act/A)
	burst()
	return HOOK_DECLINE

/// A round bursts the balloon, and that's all it does.
/obj/item/latexballon/proc/balloon_shot(datum/act/A)
	burst()
	return TRUE

/// The held thing has a point.
/obj/item/latexballon/proc/punctures(datum/act/op/A)
	return can_puncture(A.held)

/// A pointed thing bursts the balloon, and the click goes on to the ordinary attack.
/obj/item/latexballon/proc/punctured(datum/act/op/A)
	burst()
	return OP_OK
