// The melee hit of every /obj (doc/rewrite/final_api.html, section 14 "Damage"; section 9 on op tiers): the op "melee_hit" in CAPABILITIES(/obj)
// (code/datums/behaviours/burning.dm). An item in hand, a hostile stance (combat mode), the lowest tier (OP_PRIORITY_DEFAULT - 9: below every op a type
// writes, so it never clashes and every specific op answers first). The blow is the item's own force through receive_weapon_hit() (the damage
// pipeline: armour, takeovers, the integrity sink); only an item that does damage swings at all (obj_damage_type()).
//
// It is a plain op on /obj and not a library capability because /obj's table is built while the world boots, before the capability registry exists:
// a capability declared there is silently missing from every table built from it.
//
// What a type changes, it changes by procs:
//   melee_scale()    what fraction of the item's force lands (a web or a weed patch takes a quarter)
//   melee_passes()   TRUE: the blow does not use the click up, the item's own use follows (a welder still welds what it hit)
// A type that should not be hit says so with without("melee_hit") and a reason (items, effects, singularities, bellies ...); one that only some items
// may swing at it narrows the op with extend("melee_hit", when(...)); one whose blow differs in kind (a door's minimum force, a lamp that smashes)
// keeps an op of its own, which answers first.

/obj/proc/melee_scale()
	return 1

/obj/proc/melee_passes()
	return FALSE

/obj/proc/melee_hit(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	add_fingerprint(user)
	user.setClickCooldown(user.get_attack_speed(W))
	if(W.obj_damage_type())
		user.do_attack_animation(src)
		act_message(user, src, others = span_danger("%U% [LAZYLEN(W.attack_verb) ? pick(W.attack_verb) : "hits"] %T% with %I%!"), item = W)
		receive_weapon_hit(W, user, W.force * melee_scale(), silent = FALSE)
	return melee_passes() ? OP_PASS : OP_OK
