// Bluespace crystals, used in telescience and when crushed it will blink you to a random turf.

/obj/item/bluespace_crystal
	name = "bluespace crystal"
	desc = "A glowing bluespace crystal, not much is known about how they work. It looks very delicate."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "bluespace_crystal"
	w_class = ITEMSIZE_TINY
	var/blink_range = 8 // The teleport range when crushed/thrown at someone.

CAPABILITIES(/obj/item/bluespace_crystal)
	op("self", in_hand(), needs(req(PROC_REF(crystal_releasable))), then(PROC_REF(interaction_self)))
	rolls(ROLL_PIXEL, PIXEL_JITTER(5))

/// A crystal must be removable before crushing can teleport its holder.
/obj/item/bluespace_crystal/proc/crystal_releasable(datum/act/op/A)
	return A.actor ? A.actor.release_refusal(src, A.actor) : /datum/msg/req_wrong_item

/// Old attack_self.
/obj/item/bluespace_crystal/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	user.balloon_alert_visible("[user] crushes [src]!", "Crushed [src]!") // Balloon alert
	fx_sparks(get_turf(src), 5)
	blink_mob(user)
	consume(src, user)
	return TRUE

/obj/item/bluespace_crystal/proc/blink_mob(mob/living/L)
	do_teleport(L, get_turf(L), blink_range, asoundin = 'sound/effects/phasein.ogg')

/obj/item/bluespace_crystal/throw_impact(atom/hit_atom)
	if(!..()) // not caught in mid-air
		balloon_alert_visible("[src] fizzles and disappears upon impact!") // Balloon alert
		var/turf/T = get_turf(hit_atom)
		fx_sparks(T, 5)
		if(isliving(hit_atom))
			blink_mob(hit_atom)
		dephase_shadekin() // mess with shadekins
		destroyed(src, null, BRUTE)

// Artifical bluespace crystal, doesn't give you much research.

/obj/item/bluespace_crystal/artificial
	name = "artificial bluespace crystal"
	desc = "An artificially made bluespace crystal, it looks delicate."
	blink_range = 4 // Not as good as the organic stuff!
