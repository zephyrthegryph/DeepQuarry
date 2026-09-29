// drinkable(): the holder (an item with reagents) can be drunk from, a sip at a time, by its holder
// ("Drink", also its use in hand) or given to someone else ("Give a drink", timed). A sip moves
// `sip` units into the drinker (CHEM_INGEST; half for small drinkers), as standard_feed_mob() does.
// A reagent container sips its own amount_per_transfer_from_this (a per-instance setting, H1).
// With needs_open, a closed container refuses ("open it first").
//
//	/obj/item/canteen/capabilities()
//		. = ..()
//		. += drinkable(sip = 10)

/datum/capability/drinkable
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// Units one sip moves (type default).
	var/sip = 5
	var/drink_sound = SFX_ITEMS_DRINK
	/// How long giving someone a drink takes.
	var/feed_time = 3 SECONDS
	/// Refuse while the holder isn't an open container.
	var/needs_open = TRUE

/proc/drinkable(sip = 5, drink_sound = SFX_ITEMS_DRINK, feed_time = 3 SECONDS, needs_open = TRUE, behind = NONE, log = LOG_GAME)
	var/datum/capability/drinkable/C = new
	C.sip = sip
	C.drink_sound = drink_sound
	C.feed_time = feed_time
	C.needs_open = needs_open
	C.behind = behind
	C.log = log
	return C

/datum/capability/drinkable/interactions(atom/holder)
	var/datum/interaction/capability/drink = adopt_entry(hand("Drink", TYPE_PROC_REF(/obj/item, cap_drinkable_drink), behind = behind, needs = TYPE_PROC_REF(/obj/item, cap_drinkable_can_drink), works_broken = TRUE, works_unpowered = TRUE, log = log))
	drink.entry = INTERACTION_ENTRY_SELF // using it in hand drinks from it
	var/datum/interaction/capability/give = adopt_entry(hand("Give a drink", TYPE_PROC_REF(/obj/item, cap_drinkable_give), behind = behind, needs = TYPE_PROC_REF(/obj/item, cap_drinkable_can_drink), works_broken = TRUE, works_unpowered = TRUE, log = log))
	give.default_action = null // Menu only
	return list(drink, give)

/datum/capability/drinkable/examine(atom/holder, mob/user)
	if(!holder.reagents?.total_volume)
		return list("It's empty.")
	return null

/// The units one sip of I moves into drinker.
/proc/cap_drinkable_sip(obj/item/I, mob/drinker)
	var/datum/capability/drinkable/C = cap_of(I, /datum/capability/drinkable)
	var/amount = C.sip
	if(istype(I, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/RC = I
		amount = RC.amount_per_transfer_from_this || amount
	return issmall(drinker) ? CEILING(amount / 2, 1) : amount

/// One sip of I into drinker.
/proc/cap_drinkable_take_sip(obj/item/I, mob/living/drinker)
	var/datum/capability/drinkable/C = cap_of(I, /datum/capability/drinkable)
	. = I.reagents.trans_to_mob(drinker, cap_drinkable_sip(I, drinker), CHEM_INGEST)
	play_sfx(drinker, C.drink_sound)
	changed(I, CHANGE_CAPABILITY)

/obj/item/proc/cap_drinkable_can_drink(mob/user, obj/item/held)
	var/datum/capability/drinkable/C = cap_of(src, /datum/capability/drinkable)
	if(C.needs_open && !is_open_container())
		return "open it first"
	if(!reagents?.total_volume)
		return "it's empty"
	return TRUE

/obj/item/proc/cap_drinkable_drink(mob/user, obj/item/held)
	var/reason = consume_refusal(user, user, src)
	if(reason)
		return refuse(user, capitalize("[reason]."))
	user.setClickCooldown(user.get_attack_speed(src)) // a limit on how fast people can drink
	act_message(user, src, self = span_notice("You swallow a gulp from %T%."), others = span_notice("%U% drinks from %T%."))
	cap_drinkable_take_sip(src, user)
	return TRUE

/obj/item/proc/cap_drinkable_give(mob/user, obj/item/held)
	var/mob/living/target = consume_pick_target(user, src)
	if(!target)
		return UI_REFUSED
	var/reason = consume_refusal(user, target, src)
	if(reason)
		return refuse(user, capitalize("[reason]."))
	var/datum/capability/drinkable/C = cap_of(src, /datum/capability/drinkable)
	user.setClickCooldown(user.get_attack_speed(src))
	act_message(user, target, self = span_notice("You try to give %T% a drink from \the [src]."), others = span_warning("%U% tries to give %T% a drink from \the [src]."))
	om_task_timed(user, C.feed_time, target, src, PROC_REF(cap_drinkable_given), list(user, target))
	return TRUE

/// The timed drink finished: target takes a sip.
/obj/item/proc/cap_drinkable_given(mob/user, mob/living/target)
	if(!reagents?.total_volume || consume_refusal(user, target, src))
		return
	add_attack_logs(user, target, "Fed from [name] containing [reagents.get_reagents()]", admin_notify = FALSE)
	act_message(user, target, self = span_notice("You give %T% a drink from \the [src]."), others = span_notice("%U% gives %T% a drink from \the [src]."))
	cap_drinkable_take_sip(src, target)
