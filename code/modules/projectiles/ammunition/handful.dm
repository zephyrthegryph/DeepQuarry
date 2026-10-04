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
	MATERIAL_NONE
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
		move_into(H, nameof(H.stored_ammo), C, user)
	H.update_icon()
	return H

EXTEND_INTERACTIONS(/obj/item/ammo_magazine/handful, \
	INTERACT_ITEM("Combine", PROC_REF(handful_interaction_item)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(handful_interaction_hand)), \
)

/// Old attackby. FALSE: everything else (loose casing -> handful, etc.) is handled by the magazine's.
/obj/item/ammo_magazine/handful/proc/handful_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	make_rounds_real()
	// Merge two handfuls: pour the other one into this, up to capacity.
	if(istype(W, /obj/item/ammo_magazine/handful))
		. = INTERACTION_HANDLED_PASS
		var/obj/item/ammo_magazine/handful/other = W
		if(other == src)
			return
		if(other.caliber != caliber)
			to_chat(user, span_warning("Those rounds aren't the same caliber."))
			return
		var/moved = 0
		while(length(other.stored_ammo) && length(stored_ammo) < max_ammo)
			var/obj/item/ammo_casing/C = other.stored_ammo[length(other.stored_ammo)]
			rel_add(src, nameof(src.stored_ammo), C)
			moved++
		if(moved)
			to_chat(user, span_notice("You combine the rounds. \The [src] now holds [length(stored_ammo)]."))
			play_sfx(src, SFX_WEAPONS_EMPTY, 0.5)
		update_icon()
		other.update_icon()
		if(!length(other.stored_ammo))
			consume(other, user)
		return
	// Everything else (loose casing -> handful, etc.) is handled by the parent.
	return FALSE

DECLARE_APPEARANCE_PROC(/obj/item/ammo_magazine/handful, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/ammo_magazine/handful/appearance_overlays()
	. = list()
	. += ..()
	// Name tracks the count so the stack reads clearly at a glance.
	if(caliber)
		name = "handful of [caliber] rounds"

// When a handful empties through normal use, get rid of it rather than leaving an
// invisible empty stack lying around.
/// Old attack_hand, first half: taking a round out by hand (the magazine's hand effect, run here
/// so the empty check follows it). FALSE goes on to pickup; the pickup checks again after.
/obj/item/ammo_magazine/handful/proc/handful_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	. = magazine_interaction_hand(user, held, interaction)
	if(.)
		consume_if_empty(user)

EXTEND_INTERACTIONS(/obj/item/ammo_magazine/handful, INTERACT_HAND_DEFAULT("Pick up", PROC_REF(handful_pick_up)))

/// Picking a handful up: an empty one is used up.
/obj/item/ammo_magazine/handful/proc/handful_pick_up(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	interaction_pick_up(user, held, interaction)
	consume_if_empty(user)

/obj/item/ammo_magazine/handful/proc/consume_if_empty(mob/user)
	if(!QDELETED(src) && !length(stored_ammo) && loc == user)
		consume(src, user)
