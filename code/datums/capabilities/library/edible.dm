// cap_edible(): the holder (an item) can be eaten a bite at a time, by its holder ("Eat", also its use
// in hand) or fed to someone else ("Feed", a timed action). A bite moves bite_size units of its
// reagents into the eater (CHEM_INGEST, scaled by the species' bite_mod), as snacks do; without
// reagents a bite just counts. It is finished after `bites` bites or when its reagents run out,
// leaving `trash` in the eater's hand.
//
//	/obj/item/ration_bar/capabilities()
//		. = ..()
//		. += cap_edible(bites = 4, bite_size = 3, trash = /obj/item/trash/candy)
//
// The consumption checks (a mouth, nothing covering it, belly-produced reagents) are shared with
// cap_drinkable() and standard_feed_mob().

/datum/capability/edible
	data_type = /datum/cap_edible_data
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// Bites until it is finished; null: until its reagents run out (1 when it has none).
	var/bites
	/// Units of reagents one bite moves.
	var/bite_size = 1
	/// Left in the eater's hand when finished, or null.
	var/trash
	var/eat_sound = SFX_ITEMS_EATFOOD
	/// How long feeding someone else takes.
	var/feed_time = 3 SECONDS

/datum/cap_edible_data
	var/bites_taken = 0

/proc/cap_edible(bites, bite_size = 1, trash, eat_sound = SFX_ITEMS_EATFOOD, feed_time = 3 SECONDS, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/edible/C = new
	C.bites = bites
	C.bite_size = bite_size
	C.trash = trash
	C.eat_sound = eat_sound
	C.feed_time = feed_time
	cap_gating(C, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/edible/interactions(atom/holder)
	var/datum/interaction/capability/eat = adopt_entry(cap_hand("Eat", GLOBAL_PROC_REF(cap_edible_eat), needs = GLOBAL_PROC_REF(cap_edible_can_eat), works_broken = TRUE, works_unpowered = TRUE))
	eat.entry = INTERACTION_ENTRY_SELF // using it in hand eats it
	var/datum/interaction/capability/feed = adopt_entry(cap_hand("Feed", GLOBAL_PROC_REF(cap_edible_feed), works_broken = TRUE, works_unpowered = TRUE))
	feed.default_action = null // Menu only
	return list(eat, feed)

/datum/capability/edible/examine(atom/holder, mob/user)
	var/datum/cap_edible_data/D = holder.cap_data?[key]
	var/taken = D ? D.bites_taken : 0
	switch(taken)
		if(0)
			return null
		if(1)
			return list(span_notice("It was bitten by someone!"))
		if(2 to 3)
			return list(span_notice("It was bitten [taken] times!"))
	return list(span_notice("It was bitten multiple times!"))

// ---- shared consumption helpers (edible, drinkable) ----

/// Why user can't make target consume I, or null.
/proc/consume_refusal(mob/user, mob/target, obj/item/I)
	if(!istype(target) || !target.can_feed())
		return user == target ? "you can't eat or drink right now" : "\the [target] can't eat or drink"
	if(!target.consume_liquid_belly && reagents_from_belly(I))
		return "[user == target ? "you can't" : "\the [target] can't"] consume that, it contains something produced from a belly"
	return mouth_blocked_reason(user, target)

/// Asks user whom to feed I to, from the living mobs next to them. Null when cancelled.
/proc/consume_pick_target(mob/user, obj/item/I)
	var/list/candidates = list()
	for(var/mob/living/L in view(1, user))
		if(L != user)
			candidates += L
	if(!length(candidates))
		refuse(user, "There's nobody next to you to feed.")
		return null
	return ask_mob(user, "Who do you want to feed \the [I] to?", candidates, "Feed")

// ---- state ----

/// Bites taken out of I.
/proc/cap_edible_bites_taken(obj/item/I)
	var/datum/capability/edible/C = cap_of(I, /datum/capability/edible)
	var/datum/cap_edible_data/D = I.cap_data?[C?.key]
	return D ? D.bites_taken : 0

/// Whether I is eaten up.
/proc/cap_edible_finished(obj/item/I)
	var/datum/capability/edible/C = cap_of(I, /datum/capability/edible)
	var/taken = cap_edible_bites_taken(I)
	if(C.bites && taken >= C.bites)
		return TRUE
	if(I.reagents)
		return !I.reagents.total_volume
	return taken >= (C.bites || 1)

/// One bite of I into eater: reagents move, the bite counts, and a finished I becomes its trash.
/proc/cap_edible_bite(obj/item/I, mob/living/eater, mob/living/feeder)
	var/datum/capability/edible/C = cap_of(I, /datum/capability/edible)
	var/datum/cap_edible_data/D = cap_data(I, C)
	play_sfx(eater, C.eat_sound)
	if(I.reagents?.total_volume)
		var/bite_mod = 1
		var/mob/living/carbon/human/human_eater = eater
		if(istype(human_eater))
			bite_mod = human_eater.species.bite_mod
		I.reagents.trans_to_mob(eater, min(C.bite_size * bite_mod, I.reagents.total_volume), CHEM_INGEST)
	D.bites_taken++
	changed(I, CHANGE_CAPABILITY)
	if(cap_edible_finished(I))
		cap_edible_finish(I, eater)

/// I is eaten up: its trash goes to the eater's hands, and it is gone.
/proc/cap_edible_finish(obj/item/I, mob/living/eater)
	var/datum/capability/edible/C = cap_of(I, /datum/capability/edible)
	eater.balloon_alert_visible("eats \the [I].", "finishes eating \the [I].")
	if(I.loc == eater)
		eater.drop_from_inventory(I)
	if(C.trash)
		var/obj/item/trash_item = new C.trash(eater.drop_location())
		eater.put_in_hands(trash_item)
	qdel(I)

// ---- handlers ----

/proc/cap_edible_can_eat(mob/user, obj/item/holder, obj/item/held)
	if(cap_edible_finished(holder))
		return "there's none of it left"
	return TRUE

/proc/cap_edible_eat(obj/item/holder, mob/user, obj/item/held)
	var/reason = consume_refusal(user, user, holder)
	if(reason)
		return refuse(user, capitalize("[reason]."))
	user.setClickCooldown(user.get_attack_speed(holder)) // a limit on how fast people can eat
	act_message(user, holder, self = span_notice("You take a bite of %T%."), others = span_notice("%U% takes a bite of %T%."))
	cap_edible_bite(holder, user, user)
	return TRUE

/proc/cap_edible_feed(obj/item/holder, mob/user, obj/item/held)
	var/mob/living/target = consume_pick_target(user, holder)
	if(!target)
		return UI_REFUSED
	var/reason = consume_refusal(user, target, holder)
	if(reason)
		return refuse(user, capitalize("[reason]."))
	var/datum/capability/edible/C = cap_of(holder, /datum/capability/edible)
	user.setClickCooldown(user.get_attack_speed(holder))
	act_message(user, target, self = span_notice("You try to feed %T% \the [holder]."), others = span_warning("%U% tries to feed %T% \the [holder]."))
	om_task_timed(user, C.feed_time, target, holder, TYPE_PROC_REF(/obj/item, cap_edible_fed), list(user, target))
	return TRUE

/// The timed feed finished: target takes a bite.
/obj/item/proc/cap_edible_fed(mob/user, mob/living/target)
	if(cap_edible_finished(src) || consume_refusal(user, target, src))
		return
	add_attack_logs(user, target, "Fed with [name] containing [reagents ? reagents.get_reagents() : "nothing"]", admin_notify = FALSE)
	act_message(user, target, self = span_notice("You feed %T% \the [src]."), others = span_notice("%U% feeds %T% \the [src]."))
	cap_edible_bite(src, target, user)
