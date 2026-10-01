// cap_flip(): a table can be flipped on its side (a makeshift barricade) and put back. Wraps the table's
// own flipping (code/modules/tables/flipping.dm): its `flipped` var stays the truth, flip()/unflip()
// do the work (the whole straight run of matching tables goes over together, loose things on it are
// thrown), and straight_table_check()/unflipping_check() give the refusals. Tables only.
//
//	/obj/structure/table/capabilities()
//		. = ..()
//		. += cap_flip()

/datum/capability/flip
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE

/proc/cap_flip(needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/flip/C = new
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/flip/interactions(atom/holder)
	var/datum/interaction/capability/over = adopt_entry(cap_hand("Flip table", TYPE_PROC_REF(/obj/structure/table, cap_flip_over), needs = TYPE_PROC_REF(/obj/structure/table, cap_flip_can_flip), works_broken = TRUE, works_unpowered = TRUE))
	var/datum/interaction/capability/back = adopt_entry(cap_hand("Put table back", TYPE_PROC_REF(/obj/structure/table, cap_flip_back), needs = TYPE_PROC_REF(/obj/structure/table, cap_flip_can_put_back), works_broken = TRUE, works_unpowered = TRUE))
	over.default_action = null // Menu only: a click on a table puts things on it
	back.default_action = null
	return list(over, back)

/datum/capability/flip/examine(atom/holder, mob/user)
	var/obj/structure/table/T = holder
	if(istype(T) && T.flipped == 1)
		return list("It has been flipped on its side.")
	return null

/// needs: unflipped, and the run of tables beside it would go over (flip()'s own precondition).
/obj/structure/table/proc/cap_flip_can_flip(mob/user, obj/item/held)
	if(flipped != 0)
		return "it is already flipped"
	if(!user || has_trait(user, TRAIT_AMBIENT_PEST_MOB))
		return "you can't flip it"
	return can_flip_away(user, src, held)

/// needs: flipped, and nothing is in the way of putting it back.
/obj/structure/table/proc/cap_flip_can_put_back(mob/user, obj/item/held)
	if(flipped != 1)
		return "it is not flipped"
	var/result = unflipping_check()
	return istext(result) ? result : !!result

/obj/structure/table/proc/cap_flip_over(mob/user, obj/item/held)
	if(!flip(get_cardinal_dir(user, src)))
		return refuse(user, "It won't budge.")
	act_message(user, src, self = span_warning("You flip %T%!"), others = span_warning("%U% flips %T%!"))
	om_emit(src, new /datum/om/event/climb_shake(user))
	return TRUE

/obj/structure/table/proc/cap_flip_back(mob/user, obj/item/held)
	unflip()
	act_message(user, src, self = span_notice("You put %T% back on its legs."), others = span_notice("%U% puts %T% back on its legs."))
	return TRUE
