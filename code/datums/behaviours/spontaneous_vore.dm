/// Spontaneous vore (stumble/drop/throw/slip vore; was /datum/element/spontaneous_vore, then an om behaviour).
/// Four takeovers on every living mob (CAPABILITIES(/mob/living) names spontaneous_vore()): each may end the stumble, fall, thrown
/// hit or crossing because somebody was eaten instead. Each eater checks the mobs' preference flags. A handler that ate nobody
/// answers HOOK_DECLINE and the action goes on.

/proc/spontaneous_vore()
	return list(
		extend(/datum/act/stumbled_into, instead(then(TYPE_PROC_REF(/mob/living, spont_vore_stumble)))),
		extend(/datum/act/fall, instead(then(TYPE_PROC_REF(/mob/living, spont_vore_fall)))),
		extend(/datum/act/thrown_hit, instead(then(TYPE_PROC_REF(/mob/living, spont_vore_hitby)))),
		extend(/datum/act/cross, instead(then(TYPE_PROC_REF(/mob/living, spont_vore_cross)))))

/// stumbled_into: A.stumbled stumbles into the holder.
/mob/living/proc/spont_vore_stumble(datum/act/stumbled_into/A)
	return spont_vore_stumble_eat(src, A.stumbled) ? TRUE : HOOK_DECLINE

/// fall: the holder lands on A.landing (a turf), on A.landed_on (the mob there) if any.
/mob/living/proc/spont_vore_fall(datum/act/fall/A)
	return spont_vore_fall_eat(src, A.landing, A.landed_on) ? TRUE : HOOK_DECLINE

/// thrown_hit: A.thrown (thrown by A.thrower, at speed A.speed) hits the holder.
/mob/living/proc/spont_vore_hitby(datum/act/thrown_hit/A)
	return spont_vore_hitby_eat(src, A.thrown, A.thrower, A.speed) ? TRUE : HOOK_DECLINE

/// cross: A.crosser crosses into the holder.
/mob/living/proc/spont_vore_cross(datum/act/cross/A)
	return spont_vore_cross_eat(src, A.crosser) ? TRUE : HOOK_DECLINE

///Source is the one being bumped into (Owner of this component)
///Target is the one bumping into us.
/proc/spont_vore_stumble_eat(mob/living/source, mob/living/target)

	//Prevents slipping into ourselves if we have a blobform.
	if(!isturf(target.loc) || !isturf(source.loc)) //No slipping into things that aren't even on a valid turf.
		return
	//Prevents eating ourselves with our own stomach.
	if(vore_selected_of(source) == vore_selected_of(target))
		return

	//We are able to eat the person stumbling into us.
	if(can_stumble_vore(prey = target, pred = source)) //This is if the person stumbling into us is able to eat us!
		act_message(target, source, others = span_vwarning("%U% flops carelessly into %T%!"))
		var/obj/belly/destination_belly = source.get_current_spont_belly(target)
		source.begin_instant_nom(source, prey = target, pred = source, belly = destination_belly)
		target.stop_flying()
		return TRUE

	//The person stumbling into us is able to eat us.
	if(can_stumble_vore(prey = source, pred = target)) //This is if the person stumbling into us is able to be eaten by us! BROKEN!
		act_message(target, source, others = span_vwarning("%U% flops carelessly into %T%!"))
		target.forceMove(get_turf(source))
		var/obj/belly/destination_belly = target.get_current_spont_belly(source)
		source.begin_instant_nom(target, prey = source, pred = target, belly = destination_belly)
		source.stop_flying()
		return TRUE

//Source is the one dropping (us)
//Landing is the tile we're falling onto
//drop_mob is whatever mob is found in the turf we're dropping onto.
/proc/spont_vore_fall_eat(mob/living/source, turf/landing, mob/living/drop_mob)

	if(!drop_mob || drop_mob == source)
		return

	if((drop_mob.status_flags & HIDING))
		var/obj/structure/table/is_there_a_table = locate_on(landing, /obj/structure/table) //Don't eat people hiding under tables
		if(is_there_a_table)
			return

	//pred = drop_mob
	//prey = source
	//result: source is eaten by drop_mob
	if(can_drop_vore(prey = source, pred = drop_mob))
		drop_mob.feed_grabbed_to_self_falling_nom(drop_mob, prey = source)
		act_message(drop_mob, source, others = span_vdanger("%U% falls right onto %T%!"))
		return TRUE

	//pred = source
	//prey = drop_mob
	//result: drop_mob is eaten by source
	if(can_drop_vore(prey = drop_mob, pred = source))
		source.feed_grabbed_to_self_falling_nom(source, prey = drop_mob)
		source.status_at_least(STAT_WEAKENED, 4)
		act_message(drop_mob, source, others = span_vdanger("%U% falls right into %T%!"))
		return TRUE

/proc/spont_vore_hitby_eat(mob/living/source, atom/movable/hitby, mob/thrower, speed)

	//Handle object throw vore
	if(isitem(hitby))
		var/obj/item/O = hitby
		var/obj/belly/destination_belly = source.get_current_spont_belly(O)
		if(!destination_belly)
			return
		if(source.stat != DEAD && source.vore_options.trash_catching)
			if(source.vore_options.adminbus_trash || is_type_in_list(O, GLOB.edible_trash) && O.trash_eatable && !is_type_in_list(O, GLOB.item_vore_blacklist))
				act_message(source, null, others = span_vwarning("[O] is thrown directly into %U%'s [lowertext(destination_belly.name)]!"))
				destination_belly.nom_atom(O)
				return TRUE

	//Throwing a prey into a pred takes priority. After that it checks to see if the person being thrown is a pred.
	if(isliving(hitby))
		var/mob/living/thrown_mob = hitby

		//If we don't allow mobvore and the thrown mob is an NPC animal, stop here.
		if(!source.vore_prefs.allowmobvore && isanimal(thrown_mob) && !thrown_mob.ckey)
			return

		//If we're an NPC animal and the person thrown into us doesn't allow mobvore, stop here.
		if(!thrown_mob.vore_prefs.allowmobvore && isanimal(source) && !source.ckey)
			return

		// PERSON BEING HIT: CAN BE DROP PRED, ALLOWS THROW VORE.
		// PERSON BEING THROWN: DEVOURABLE, ALLOWS THROW VORE, CAN BE DROP PREY.
		if(can_throw_vore(prey = thrown_mob, pred = source))
			var/obj/belly/destination_belly = source.get_current_spont_belly(thrown_mob)
			if(!destination_belly)
				return
			destination_belly.nom_atom(thrown_mob) //Eat them!!!
			act_message(thrown_mob, source, others = span_vwarning("%U% is thrown right into %T%'s [lowertext(destination_belly.name)]!"))
			source.on_throw_vore_special(TRUE, thrown_mob)

			if(thrower)
				add_attack_logs(thrower,source,"Devoured [thrown_mob.name] via throw vore.")
			else
				log_vore("[source] devoured [thrown_mob.name] via throw vore.")
			return TRUE //We can stop here. We don't need to calculate damage or anything else. They're eaten.

		// PERSON BEING HIT: CAN BE DROP PREY, ALLOWS THROW VORE, AND IS DEVOURABLE.
		// PERSON BEING THROWN: CAN BE DROP PRED, ALLOWS THROW VORE.
		else if(can_throw_vore(prey = source, pred = thrown_mob))//Pred thrown into prey.
			var/obj/belly/destination_belly = thrown_mob.get_current_spont_belly(source)
			if(!destination_belly)
				return
			act_message(source, thrown_mob, others = span_vwarning("%U% suddenly slips inside of %T%'s [lowertext(destination_belly.name)] as %T% flies into them!"))
			destination_belly.nom_atom(source) //Eat them!!!
			if(source.loc != vore_selected_of(thrown_mob))
				vore_selected_of(thrown_mob).belly_insert(source) //Double check. Should never happen but...Weirder things have happened!
			if(thrower)
				add_attack_logs(thrower,source,"Was Devoured by [thrown_mob.name] via throw vore.")
			else
				log_vore("[source] Was Devoured by [thrown_mob.name] via throw vore.")
			return TRUE

//source = person standing up
//crossed = person sliding
/proc/spont_vore_cross_eat(mob/living/source, mob/living/crossed)

	if(source == crossed || !istype(crossed))
		return


	//Person being slipped into eats the person slipping
	if(can_slip_vore(pred = source, prey = crossed))	//If we can vore them go for it
		var/obj/belly/destination_belly = source.get_current_spont_belly(crossed)
		if(!destination_belly)
			return
		source.begin_instant_nom(source, prey = crossed, pred = source, belly = destination_belly)
		return TRUE

	//The person slipping eats the person being slipped into
	else if(can_slip_vore(pred = crossed, prey = source))
		var/obj/belly/destination_belly = crossed.get_current_spont_belly(source)
		if(!destination_belly)
			return
		source.begin_instant_nom(crossed, prey = source, pred = crossed, belly = destination_belly) //Must be
		return //We DON'T block it here. Pred can slip onto the prey's tile, no problem.
