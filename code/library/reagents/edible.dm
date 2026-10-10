// edible(...) (doc/rewrite/final_api.html, section 11 "Reagents and food"; section 16.5): a thing that is eaten a bite at a time, by the one who holds it or by
// someone it is fed to, or swallowed whole by the one who is stuffed with it. On top of reagent holders: what a bite is, is a number of units that go into the
// eater (the species decides how big a bite it takes); the thing is finished when a bite leaves nothing, and what finishing does is the holder type's own.
//
//   CAPABILITIES(/obj/item/reagent_containers/food/snacks,
//       edible(bite = nameof(bitesize), taken = nameof(bitecount), sound = nameof(eating_sound), survival = nameof(survivalfood),
//           shut = list(nameof(package) = MSG(edible/wrapped), nameof(canned) = MSG(edible/sealed))))
//
// A setting is a number or the name of a var of the holder that says it (a type then keeps it on its own var line). `shut` maps the name of a holder var
// to the reason it gives while it is true: nothing is eaten, fed or swallowed while the food is wrapped or sealed. `survival` names the holder var that is
// TRUE for food a mask that allows survival rations lets through. `taken` names the holder var that counts the bites.
//
// Ops (all "edible.<name>"):
//   eat      a click on yourself, in any stance: one bite, into the stomach. A mouth, nothing over it, a stomach with room and no belly-made reagents.
//   feed     a click on somebody else in a stance that does no harm: after `feed_wait`, the same bite into them
//   stuff    a click on somebody else, by someone who feeds whole (stuffing_feeder): the food goes whole into the belly they choose of the one fed, after
//            `whole_wait` (`other_wait` when the one fed is not a person with a mouth)
//   used_up  a click on yourself with a food with nothing left in it: it is used up
//
// A bite is one RES_REAGENTS transaction (REAGENT_FLOW_INGEST) like a drink's sip. What a bite leaves behind (a finished food's trash, a tiny person who is
// swallowed, a contract event) is the holder's On_Consume(eater, feeder), called a moment after the bite has gone in (edible_aftermath()).

CAPABILITY_TYPE(edible, CAP_EDIBLE, /datum/capability/lib/edible, key = NONE, bite = 1, taken = null, sound = null, survival = null, shut = null, feed_wait = 30, whole_wait = 50, other_wait = 30, fullness_limit = 6000)

MSG_DEF_SELF(edible/wrapped, "The package is in the way!")
MSG_DEF_SELF(edible/sealed, "The can is closed!")
MSG_DEF_SELF(edible/none_left, "There is none of it left!")
MSG_DEF_SELF(edible/no_mouth, "There is no mouth to put it in!")
MSG_DEF_SELF(edible/mouth_covered, "Something is in the way of the mouth!")
MSG_DEF_SELF(edible/unconscious, "You can't feed them through what is over their mouth while they are unconscious!")
MSG_DEF_SELF(edible/too_full, "Nope. That's it. You literally cannot force any more of it to go down your throat. It's fair to say you're full.")
MSG_DEF_SELF(edible/no_whole_feeding, "They refuse to be fed whole things!")
MSG_DEF_SELF(edible/no_belly, "They don't appear to have a belly to fit it!")
MSG_DEF_SELF(edible/from_belly, "That contains something produced from a belly, and it won't be taken.")
MSG_DEF(edible/begin_feed, "You attempt to feed %T% %I%.", "%U% attempts to feed %T% %I%.")
MSG_DEF(edible/fed, "You feed %T% %I%.", "%U% feeds %T% %I%.")
MSG_DEF(edible/begin_stuff, "You attempt to make %T% consume %I% whole.", "%U% attempts to make %T% consume %I% whole.")
MSG_DEF(edible/stuffed, "You force %I% into %T%.", "%U% successfully forces %I% into %T%.")
MSG_DEF(edible/eat, "You take a bite of %I%.", "%U% takes a bite of %I%.")

/datum/capability/lib/edible/entries()
	return list(
		op("used_up", at_target(/mob/living/carbon), when(cond_all(CAP_PROC(targets_self), cond_not(req(CAP_PROC(has_reagents))))), priority(OP_PRIORITY_PART + 2), label("Eat"),
			then(CAP_PROC(thrown_away))),
		op("eat", at_target(/mob/living/carbon), when(CAP_PROC(targets_self)), priority(OP_PRIORITY_PART), label("Eat"),
			needs(req(CAP_PROC(is_open)), req(CAP_PROC(belly_free)),
				req(CAP_PROC(mouth_present)), req(CAP_PROC(mouth_clear)),
				req(CAP_PROC(room_in_stomach))),
			costs(RES_REAGENTS, CAP_PROC(bite_amount)), then(CAP_PROC(eaten))),
		op("feed", at_target(/mob/living/carbon/human), when(cond_all(cond_not(CAP_PROC(targets_self)), cond_not(CAP_PROC(feeds_whole)))), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_PART), label("Feed"),
			begins(MSG(edible/begin_feed)), wait(CAP_PROC(feed_time)),
			needs(req(CAP_PROC(is_open)), req(CAP_PROC(has_reagents)), req(CAP_PROC(belly_free)),
				req(CAP_PROC(mouth_present)), req(CAP_PROC(mouth_clear)),
				req(CAP_PROC(awake_or_open_mouthed))),
			costs(RES_REAGENTS, CAP_PROC(bite_amount)), then(CAP_PROC(fed)), says(MSG(edible/fed))),
		op("stuff", at_target(/mob/living/carbon/human), when(cond_all(cond_not(CAP_PROC(targets_self)), CAP_PROC(feeds_whole))), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_PART + 1), label("Feed whole"),
			asks(/datum/prompt/choice, fields = list("question" = "Choose Belly", "title" = "Belly Choice", "choices" = computed(CAP_PROC(belly_choices)))),
			begins(MSG(edible/begin_stuff)), wait(CAP_PROC(whole_time)),
			needs(req(CAP_PROC(is_open)), req(CAP_PROC(awake_or_open_mouthed)), req(CAP_PROC(mouth_present)),
				req(CAP_PROC(mouth_clear)), req(CAP_PROC(takes_whole_feeding))),
			then(CAP_PROC(swallowed_whole)), says(MSG(edible/stuffed))),
		op("stuff_other", at_target(/mob/living), when(cond_all(cond_not(CAP_PROC(is_carbon_target)), CAP_PROC(feeds_whole))), priority(OP_PRIORITY_PART + 1), label("Feed whole"),
			asks(/datum/prompt/choice, fields = list("question" = "Choose Belly", "title" = "Belly Choice", "choices" = computed(CAP_PROC(belly_choices)))),
			begins(MSG(edible/begin_stuff)), wait(CAP_PROC(other_time)),
			needs(req(CAP_PROC(takes_whole_feeding))),
			then(CAP_PROC(swallowed_whole)), says(MSG(edible/stuffed))))

// ---- settings ----

/// A setting: the value written in the declaration, or what the holder's var of that name says now; `fallback` when neither is a value.
/datum/capability/lib/edible/proc/setting(atom/holder, value, fallback)
	if(istext(value))
		value = holder.vars[value]
	return isnull(value) ? fallback : value

// ---- what a click is ----

/datum/capability/lib/edible/proc/targets_self(datum/act/op/A)
	return !isnull(A.target) && A.target == A.actor

/// The one clicking feeds things whole to others (a pref of theirs).
/datum/capability/lib/edible/proc/feeds_whole(datum/act/op/A)
	var/mob/living/feeder = A.actor
	return isliving(feeder) && feeder.stuffing_feeder

/datum/capability/lib/edible/proc/is_carbon_target(datum/act/op/A)
	return iscarbon(A.target)

// ---- requirements (x(datum/act/op/A), pure) ----

/// The name of the first of the holder's `shut` vars that is true, or null.
/datum/capability/lib/edible/proc/shut_var(atom/holder)
	for(var/var_name in shut)
		if(holder.vars[var_name])
			return var_name
	return null

/datum/capability/lib/edible/proc/is_open(datum/act/op/A)
	var/var_name = shut_var(A.holder)
	return isnull(var_name) ? null : req_refusal_value(shut[var_name], /datum/msg/req_failed)

/datum/capability/lib/edible/proc/has_reagents(datum/act/op/A)
	var/atom/holder = A.holder
	return (!!holder.reagents?.total_volume) ? null : /datum/msg/edible/none_left

/// What is in it may be given to this one: a mob that does not take what a belly made refuses it.
/datum/capability/lib/edible/proc/belly_free(datum/act/op/A)
	var/mob/target = A.target
	return (!istype(target) || target.consume_liquid_belly || !reagents_from_belly(A.holder)) ? null : /datum/msg/edible/from_belly

/// The one eaten by has a mouth (only a person can lack one).
/datum/capability/lib/edible/proc/mouth_present(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	return (!istype(target) || !!target.check_has_mouth()) ? null : /datum/msg/edible/no_mouth

/// Nothing over the mouth that stops this food (survival food passes what allows survival rations).
/datum/capability/lib/edible/proc/mouth_clear(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	if(!istype(target))
		return null
	var/atom/holder = A.holder
	if(setting(holder, survival, FALSE))
		return (isnull(target.check_mouth_coverage_survival())) ? null : /datum/msg/edible/mouth_covered
	return (isnull(target.check_mouth_coverage())) ? null : /datum/msg/edible/mouth_covered

/// Survival food is fed to an unconscious person only when nothing at all covers the mouth.
/datum/capability/lib/edible/proc/awake_or_open_mouthed(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	if(!istype(target))
		return null
	var/atom/holder = A.holder
	if(setting(holder, survival, FALSE) && target.stat && target.check_mouth_coverage())
		return /datum/msg/edible/unconscious
	return null

/// How full the stomach is: its nutrition and the nutriment in it, as the old messages counted.
/datum/capability/lib/edible/proc/fullness_of(mob/living/eater)
	return eater.nutrition + (eater.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT) * 25)

/datum/capability/lib/edible/proc/room_in_stomach(datum/act/op/A)
	var/mob/living/eater = A.target
	return (!istype(eater) || fullness_of(eater) <= fullness_limit) ? null : /datum/msg/edible/too_full

/// The one fed takes whole things: they permit it, and have a belly to take it.
/datum/capability/lib/edible/proc/takes_whole_feeding(datum/act/op/A)
	var/mob/living/target = A.target
	return (!!target.feeding && length(target.feedable_bellies()) > 0) ? null : /datum/msg/edible/no_whole_feeding

/// The bellies the one fed has that take food.
/datum/capability/lib/edible/proc/belly_choices(datum/act/op/A)
	var/mob/living/target = A.target
	return target.feedable_bellies()

// ---- how long and how much ----

/datum/capability/lib/edible/proc/feed_time(datum/act/op/A)
	return feed_wait

/datum/capability/lib/edible/proc/whole_time(datum/act/op/A)
	return whole_wait

/datum/capability/lib/edible/proc/other_time(datum/act/op/A)
	return other_wait

/// (source, sink, mode) of a bite: the food into the one eating.
/datum/capability/lib/edible/proc/flow_of(datum/act/op/A)
	return list(A.holder, A.target, REAGENT_FLOW_INGEST)

/// One bite: the amount set times what the eater's species takes at once, and no more than there is.
/datum/capability/lib/edible/proc/bite_amount(datum/act/op/A)
	var/atom/holder = A.holder
	var/size = setting(holder, bite, 1)
	var/mob/living/carbon/human/eater = A.target
	if(istype(eater))
		size *= eater.species.bite_mod
	return min(size, reagents_giveable(holder))

// ---- effects ----

/// Whether `food` says something about being used up, a thing with nothing left is gone.
/datum/capability/lib/edible/proc/thrown_away(datum/act/op/A)
	var/atom/movable/holder = A.holder
	holder.balloon_alert(A.actor, "none of \the [holder] left!")
	consume(holder, A.actor)
	return OP_OK

/// The lines of what a person says as they eat, by how full they were: the more full, the less they like it.
/datum/capability/lib/edible/proc/fullness_line(mob/living/eater, atom/holder, fullness)
	switch(fullness)
		if(-INFINITY to 50)
			to_chat(eater, span_danger("You hungrily chew out a piece of [holder] and gobble it!"))
		if(50 to 150)
			to_chat(eater, span_notice("You hungrily begin to eat [holder]."))
		if(150 to 350)
			to_chat(eater, span_notice("You take a bite of [holder]."))
		if(350 to 550)
			to_chat(eater, span_notice("You chew a bit of [holder], despite feeling rather full."))
		if(550 to 650)
			to_chat(eater, span_notice("You swallow some more of the [holder], causing your belly to swell out a little."))
		if(650 to 1000)
			to_chat(eater, span_notice("You stuff yourself with the [holder]. Your stomach feels very heavy."))
		if(1000 to 3000)
			to_chat(eater, span_notice("You swallow down the hunk of [holder]. Surely you have to have some limits?"))
		if(3000 to 5500)
			to_chat(eater, span_danger("You force the piece of [holder] down. You can feel your stomach getting firm as it reaches its limits."))
		if(5500 to 6000)
			to_chat(eater, span_danger("You glug down the bite of [holder], you are reaching the very limits of what you can eat, but maybe a few more bites could be managed..."))

/// A bite counted, heard, and (a moment after it has gone in) what it did to the food: the holder's On_Consume.
/datum/capability/lib/edible/proc/bitten(datum/act/op/A, mob/living/eater, mob/feeder)
	var/atom/holder = A.holder
	if(!isnull(taken))
		holder.vars[taken] = (holder.vars[taken] || 0) + 1 // ALLOW(api): the bite count is the holder var the declaration names
	var/eat_sound = setting(holder, sound, null)
	if(eat_sound)
		play_sfx(eater, eat_sound, volume = rand(10, 50))
	after(holder, 1 TICK, GLOBAL_PROC_REF(edible_aftermath), key = "bitten", with = list(holder, eater, feeder))

/// A bite of your own: the click's time, what you say about how full you are, the bite.
/datum/capability/lib/edible/proc/eaten(datum/act/op/A)
	var/mob/living/eater = A.target
	var/obj/item/holder = A.holder
	eater.setClickCooldown(eater.get_attack_speed(holder)) // a limit on how fast people can eat
	fullness_line(eater, holder, fullness_of(eater))
	bitten(A, eater, eater)
	return OP_OK

/// A bite fed to somebody: the one feeding pays the click's time, the log says who fed whom with what, and the bite goes in.
/datum/capability/lib/edible/proc/fed(datum/act/op/A)
	var/mob/living/eater = A.target
	var/mob/user = A.actor
	var/obj/item/holder = A.holder
	user.setClickCooldown(user.get_attack_speed(holder))
	add_attack_logs(user, eater, "Fed with [holder.name] containing [holder.reagents ? holder.reagents.get_reagents() : "nothing"]", admin_notify = FALSE)
	bitten(A, eater, user)
	return OP_OK

/// The food goes whole into the belly that was chosen.
/datum/capability/lib/edible/proc/swallowed_whole(datum/act/op/A)
	var/mob/living/eater = A.target
	var/mob/living/user = A.actor
	var/obj/item/holder = A.holder
	var/datum/prompt/R = A.answer
	var/obj/belly/belly_target = R?.value
	if(!belly_target)
		A.reason = /datum/msg/edible/no_belly
		return OP_REFUSED
	user.setClickCooldown(user.get_attack_speed(holder))
	add_attack_logs(user, eater, "Whole-fed with [holder.name] containing [holder.reagents ? holder.reagents.get_reagents() : "nothing"] into [belly_target]", admin_notify = FALSE)
	user.drop_item()
	if(!move_into(belly_target, BELLY_SLOT_INTERIOR, holder, user))
		holder.forceMove(get_turf(user))
	return OP_OK

/// What a bite leaves behind, a moment after it has gone in: the holder's own On_Consume(eater, feeder), if it has one.
/proc/edible_aftermath(atom/holder, mob/living/eater, mob/living/feeder)
	if(QDELETED(holder) || !hascall(holder, "On_Consume"))
		return
	call(holder, "On_Consume")(eater, feeder)
