/*
 * Casing handfuls.
 *
 * A handful is an emergent, caliber-generic stack of loose rounds that the player
 * BUILDS from brass they pick up off the ground — the "scavenge your casings and
 * thumb them back into the gun" loop from TGMC / Eris.  It is distinct from a
 * /obj/item/ammo_magazine/clip, which is a pre-defined, caliber-specific spawn item.
 *
 * It is implemented as a thin /obj/item/ammo_magazine subtype so it reuses all the
 * existing machinery for free:
 *   - add a loose round:      click a casing onto the handful  (ammo_magazine/attackby)
 *   - take one back:          take it from your off-hand        (ammo_magazine/attack_hand)
 *   - sweep up floor brass:   click the handful onto a casing   (ammo_casing/attackby)
 * The only genuinely new interactions live here + two small hooks elsewhere:
 *   - FORM a handful:         click one loose casing onto another  (ammo_casing/attackby)
 *   - MERGE two handfuls:     click a handful onto a handful        (below)
 *   - FEED a gun:             click the handful onto a compatible gun (gun/projectile/load_ammo)
 */

/obj/item/ammo_magazine/handful
	name = "handful of ammo"
	desc = "A loose handful of rounds, gathered to be thumbed into a gun one at a time."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "s-casing"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_BELT | SLOT_EARS
	matter = null
	throwforce = 1
	mag_type = SPEEDLOADER	//feeds revolvers / shotguns / internal-mag guns via load_ammo
	caliber = ""			//inherited from the first round gathered
	max_ammo = 8
	initial_ammo = 0		//never spawns pre-filled; only ever built from loose brass
	multiple_sprites = 0

/// Build a fresh handful holding the two supplied casings (same caliber assumed).
/// Returns the handful, or null on failure.
/proc/make_ammo_handful(obj/item/ammo_casing/a, obj/item/ammo_casing/b, mob/user)
	if(QDELETED(a) || QDELETED(b) || a.caliber != b.caliber)
		return null
	var/obj/item/ammo_magazine/handful/H = new(get_turf(a))
	H.caliber = a.caliber
	H.name = "handful of [a.caliber] rounds"
	for(var/obj/item/ammo_casing/C in list(a, b))
		if(user)
			user.remove_from_mob(C)
		C.forceMove(H)
		H.stored_ammo += C
	H.update_icon()
	return H

/obj/item/ammo_magazine/handful/attackby(obj/item/W, mob/user)
	// Merge two handfuls: pour the other one into this, up to capacity.
	if(istype(W, /obj/item/ammo_magazine/handful))
		var/obj/item/ammo_magazine/handful/other = W
		if(other == src)
			return
		if(other.caliber != caliber)
			to_chat(user, span_warning("Those rounds aren't the same caliber."))
			return
		var/moved = 0
		while(other.stored_ammo.len && stored_ammo.len < max_ammo)
			var/obj/item/ammo_casing/C = other.stored_ammo[other.stored_ammo.len]
			other.stored_ammo -= C
			C.forceMove(src)
			stored_ammo += C
			moved++
		if(moved)
			to_chat(user, span_notice("You combine the rounds. \The [src] now holds [stored_ammo.len]."))
			playsound(src, 'sound/weapons/empty.ogg', 25, 1)
		update_icon()
		other.update_icon()
		if(!other.stored_ammo.len)
			qdel(other)
		return
	// Everything else (loose casing -> handful, etc.) is handled by the parent.
	return ..()

/obj/item/ammo_magazine/handful/update_icon()
	..()
	// Name tracks the count so the stack reads clearly at a glance.
	if(caliber)
		name = "handful of [caliber] rounds"

// When a handful empties through normal use, get rid of it rather than leaving an
// invisible empty stack lying around.
/obj/item/ammo_magazine/handful/attack_hand(mob/user)
	..()
	if(!QDELETED(src) && !stored_ammo.len && loc == user)
		qdel(src)
