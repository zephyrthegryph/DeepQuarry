// damageable(): the holder takes a blow from an item swung at it (doc/rewrite/final_api.html, section 14 "Damage"; section 9 on op tiers).
//
// One op, "damageable.hit": an item in hand, a hostile stance (combat mode), the lowest tier, so every specific op of the holder (a tool, a card, a
// part) answers first. The blow is the item's own force through receive_weapon_hit() (the damage pipeline: armour, takeovers, the integrity sink),
// and only an item that does damage swings at all (obj_damage_type()). A type that should not be hit does not declare it, and a click that no op of
// a target answers gets the engine's gate feedback or the held item's own use: there is no default hit behind the ops.
//
//   CAPABILITIES(/obj/structure/closet, damageable())
//
// This replaces the per-type "strike" / "hit" ops whose effect was this one (the closet's); types whose blow differs (a door's minimum force, a
// barricade's welder) keep their own until their numbers are parameters here.

CAPABILITY_TYPE(damageable, CAP_DAMAGEABLE, /datum/capability/lib/damageable, key = NONE)

/datum/capability/lib/damageable

/datum/capability/lib/damageable/entries()
	return list(op("hit", item(/obj/item), hostile(), priority(OP_PRIORITY_DEFAULT - 1), label("Hit"), then(CAP_PROC(hit_with))))

/datum/capability/lib/damageable/proc/hit_with(datum/act/op/A)
	var/atom/holder = A.holder
	var/mob/user = A.actor
	var/obj/item/W = A.held
	holder.add_fingerprint(user)
	user.setClickCooldown(user.get_attack_speed(W))
	if(W.obj_damage_type())
		user.do_attack_animation(holder)
		act_message(user, holder, others = span_danger("%U% hits %T% with %I%!"), item = W)
		holder.receive_weapon_hit(W, user, silent = FALSE)
	return OP_OK
